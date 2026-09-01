package net.kashi.particles.runtime;

import com.mojang.blaze3d.vertex.VertexConsumer;

import net.kashi.particles.core.KashiParticleDefinition;
import net.kashi.particles.core.KashiParticleDefinition.Flipbook;
import net.kashi.particles.core.KashiParticleDefinition.GradientStop;
import net.kashi.particles.core.KashiParticleDefinition.Uv;
import net.kashi.particles.core.molang.MolangContext;
import net.kashi.particles.core.molang.MolangContext.Var;
import net.kashi.particles.core.molang.MolangValue;

import net.minecraft.client.Camera;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.util.Mth;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import java.util.List;

/**
 * One visible KASHI billboard.
 *
 * <p>Reproduces the Bedrock particle as Wintersky (Snowstorm's runtime) does: spawn-time values â€”
 * the four particle randoms, the lifetime, and the initial rotation â€” are frozen at birth, while
 * size, tint and the flipbook frame are re-evaluated every frame against the particle's MoLang
 * context. Bedrock times are in seconds; Minecraft ticks are 1/20 s, so ages are converted.
 */
public class KashiParticle extends Particle {

	private static final int FULL_BRIGHT = 0xF000F0;

	private final KashiCompiledEffect effect;
	private final MolangContext context;
	private final KashiEmitterParticle emitter;

	// Compiled once per particle from the shared effect; evaluated per frame.
	private final MolangValue sizeX;
	private final MolangValue sizeY;
	private final MolangValue tintInterpolant;

	/** Ends the particle early when non-zero; null when the effect does not define one. */
	private final MolangValue expiration;

	private final float lifetimeSeconds;
	private final float initialRotationDeg;
	private final float rotationRateDeg;

	// Velocity in metres per second (Bedrock's unit), not Minecraft's per-tick deltas.
	private double vx;
	private double vy;
	private double vz;

	private int timelineFired;
	private boolean expirationFired;

	// Scratch objects reused across render() calls so the hot per-frame path allocates nothing.
	// A single effect routinely has thousands of live particles, each rendered every frame (not
	// just every tick) - `new`ing half a dozen small JOML objects and float[4]s per particle per
	// frame is real, measurable garbage-collector pressure, and GC pauses are the classic cause of
	// periodic stutter. Each field is written before every read within one render() call, so
	// reusing them across frames is safe - nothing outside this instance ever holds onto a
	// reference to them.
	private final Quaternionf facingScratch = new Quaternionf();
	private final Vector3f travelScratch = new Vector3f();
	private final Vector3f axisScratch = new Vector3f();
	private final Vector3f normalScratch = new Vector3f();
	private final Vector3f forwardScratch = new Vector3f();
	private final Vector3f crossScratch = new Vector3f();
	private final Vector3f vertexScratch = new Vector3f();
	private final float[] uvScratch = new float[4];
	private final float[] tintScratch = new float[4];

	/** Guards against telling the emitter twice that this particle died. */
	private boolean releasedSlot;

	/** Set by parametric motion; overrides the spin from particle_initial_spin when in use. */
	private float parametricRotationDeg;

	/**
	 * @param spawnContext the context the emitter already used to place this particle - its four
	 *                     randoms are rolled there and must be reused here, or a random that
	 *                     decided the spawn position would differ from the one the size or colour
	 *                     expression reads.
	 */
	KashiParticle(ClientLevel level, double x, double y, double z, KashiEmitterParticle emitter,
			KashiCompiledEffect effect, MolangContext spawnContext,
			double dirX, double dirY, double dirZ) {
		super(level, x, y, z);

		this.effect = effect;
		this.emitter = emitter;
		this.context = spawnContext;

		KashiParticleDefinition d = effect.definition();

		// --- lifetime: evaluated once, then fixed ---
		double life = Math.max(0.05, effect.compile(d.particleLifetime().maxLifetime()).eval(this.context));
		this.lifetimeSeconds = (float) life;
		this.context.set(Var.PARTICLE_LIFETIME, life);
		this.lifetime = Math.max(1, Mth.ceil(life * 20.0));
		// The particle's own lifetime is the usual horizontal range of a curve, so the curves are
		// only meaningful once it is known - and everything below reads them.
		effect.applyCurves(this.context);

		// --- initial rotation and spin, frozen at birth like Wintersky ---
		if (d.initialSpin() != null) {
			this.initialRotationDeg = (float) effect.compile(d.initialSpin().rotation()).eval(this.context);
			this.rotationRateDeg = (float) effect.compile(d.initialSpin().rotationRate()).eval(this.context);
		} else {
			this.initialRotationDeg = 0;
			this.rotationRateDeg = 0;
		}

		// --- initial speed: a scalar rides the spawn direction, a vector replaces it ---
		switch (d.initialSpeed()) {
			case KashiParticleDefinition.InitialSpeed.AlongDirection along -> {
				double speed = effect.compile(along.speed()).eval(this.context);

				this.vx = dirX * speed;
				this.vy = dirY * speed;
				this.vz = dirZ * speed;
			}
			case KashiParticleDefinition.InitialSpeed.Velocity explicit -> {
				// An explicit velocity is authored in emitter-local axes, so it has to be turned
				// by the same aim that turned the spawn offset, or a fired effect would launch its
				// particles along world axes while its shape leaned elsewhere.
				Vector3f velocity = new Vector3f(
						(float) effect.compile(explicit.velocity().x()).eval(this.context),
						(float) effect.compile(explicit.velocity().y()).eval(this.context),
						(float) effect.compile(explicit.velocity().z()).eval(this.context));

				emitter.rotateByAim(velocity);

				this.vx = velocity.x();
				this.vy = velocity.y();
				this.vz = velocity.z();
			}
			case null -> { }
		}

		// local_space.velocity: born already moving with whatever fired the effect, so a trail
		// left by a running player streams behind instead of hanging in the air.
		net.minecraft.world.phys.Vec3 inherited = emitter.inheritedVelocity();

		this.vx += inherited.x;
		this.vy += inherited.y;
		this.vz += inherited.z;

		this.sizeX = effect.compile(d.appearance().size().x());
		this.sizeY = effect.compile(d.appearance().size().y());
		this.tintInterpolant = d.tinting() != null && d.tinting().interpolant() != null
				? effect.compile(d.tinting().interpolant()) : null;

		// A constant-zero expiration is Bedrock's "never expire early"; skip it rather than
		// evaluating a no-op every tick.
		this.expiration = d.particleLifetime().expiration().isConstant()
				&& d.particleLifetime().expiration().constantValue() == 0
						? null : effect.compile(d.particleLifetime().expiration());

		this.roll = (float) Math.toRadians(this.initialRotationDeg);
		this.oRoll = this.roll;

		this.emitter.fireParticleEvents(
				d.particleEvents().creation(), this.context, this.x, this.y, this.z);
	}

	/**
	 * Ends the particle, firing its expiration events first.
	 *
	 * <p>A particle that spawns something where it died is how trails and impacts are built, so
	 * this has to happen before removal and exactly once â€” every path out of a particle's life
	 * comes through here.
	 */
	private void expire() {
		if (!this.expirationFired) {
			this.expirationFired = true;

			this.emitter.fireParticleEvents(this.effect.definition().particleEvents().expiration(),
					this.context, this.x, this.y, this.z);
		}

		this.remove();
	}

	/** Fires the timeline entries that have come due, each exactly once. */
	private void fireDueEvents(double ageSeconds) {
		List<KashiParticleDefinition.TimedEvents> timeline =
				this.effect.definition().particleEvents().timeline();

		while (this.timelineFired < timeline.size()
				&& timeline.get(this.timelineFired).at() <= ageSeconds) {
			this.emitter.fireParticleEvents(timeline.get(this.timelineFired).events(),
					this.context, this.x, this.y, this.z);

			this.timelineFired++;
		}
	}

	@Override
	public void tick() {
		this.xo = this.x;
		this.yo = this.y;
		this.zo = this.z;
		this.oRoll = this.roll;

		if (this.age++ >= this.lifetime) {
			expire();
			return;
		}

		// Applied after xo/yo/zo were saved, so the follow is part of this tick's movement and the
		// renderer interpolates through it instead of snapping once per tick.
		followEmitter();

		double ageSeconds = this.age / 20.0;
		this.context.set(Var.PARTICLE_AGE, ageSeconds);
		this.context.inheritEmitterState(this.emitter.context());
		this.effect.applyCurves(this.context);

		// Per-update first: a variable it drives can be read by motion, size or the expiration test
		// on this same tick.
		KashiParticleDefinition.ParticleInitialization init = this.effect.definition().particleInit();

		if (init != null)
			this.effect.compile(init.perUpdate()).eval(this.context);

		// expiration_expression ends the particle early, before its max_lifetime is up.
		if (this.expiration != null && this.expiration.eval(this.context) != 0) {
			expire();
			return;
		}

		fireDueEvents(ageSeconds);
		applyMotion();

		// Checked after the move, so a particle that crossed the plane or entered a block this
		// tick dies at the position that put it there rather than one tick later.
		if (killedByWorld())
			expire();

		this.roll = this.effect.definition().motionParametric() != null
				? (float) Math.toRadians(this.parametricRotationDeg)
				: (float) Math.toRadians(this.initialRotationDeg + this.rotationRateDeg * ageSeconds);
	}

	/**
	 * Carries the particle along with an emitter that is following an entity â€”
	 * {@code minecraft:emitter_local_space}.
	 *
	 * <p>Position is carried by moving the particle the same amount the emitter moved; rotation by
	 * swinging its offset from the emitter, and its velocity, through the same turn. Doing it as a
	 * delta rather than by storing emitter-relative coordinates keeps the particle's own motion
	 * integration untouched.
	 *
	 * <p>Parametric motion is left alone: it already states the position relative to the emitter
	 * each tick, so it follows for free and carrying it as well would move it twice.
	 */
	private void followEmitter() {
		if (!this.emitter.carriesParticles() || this.effect.definition().motionParametric() != null)
			return;

		if (this.emitter.turnsParticles()) {
			Quaternionf turn = this.emitter.carryRotation();

			// The emitter has already moved this tick, so its offset is measured from where it was.
			Vector3f offset = new Vector3f(
					(float) (this.x - (this.emitter.originX() - this.emitter.carryX())),
					(float) (this.y - (this.emitter.originY() - this.emitter.carryY())),
					(float) (this.z - (this.emitter.originZ() - this.emitter.carryZ())));

			Vector3f turned = turn.transform(new Vector3f(offset));

			this.x += turned.x() - offset.x();
			this.y += turned.y() - offset.y();
			this.z += turned.z() - offset.z();

			Vector3f velocity = turn.transform(
					new Vector3f((float) this.vx, (float) this.vy, (float) this.vz));

			this.vx = velocity.x();
			this.vy = velocity.y();
			this.vz = velocity.z();
		}

		this.x += this.emitter.carryX();
		this.y += this.emitter.carryY();
		this.z += this.emitter.carryZ();
	}

	/**
	 * Moves the particle one tick.
	 *
	 * <p>Parametric motion wins when present: it states the position outright, relative to the
	 * emitter, so integrating velocity as well would fight it.
	 */
	private void applyMotion() {
		KashiParticleDefinition.MotionParametric parametric = this.effect.definition().motionParametric();

		if (parametric != null) {
			applyParametricMotion(parametric);
			return;
		}

		applyDynamicMotion();
	}

	/** Position dictated by expression, measured from the emitter and rotated by its aim. */
	private void applyParametricMotion(KashiParticleDefinition.MotionParametric parametric) {
		Vector3f relative = new Vector3f(
				(float) this.effect.compile(parametric.relativePosition().x()).eval(this.context),
				(float) this.effect.compile(parametric.relativePosition().y()).eval(this.context),
				(float) this.effect.compile(parametric.relativePosition().z()).eval(this.context));

		this.emitter.rotateByAim(relative);

		this.x = this.emitter.originX() + relative.x();
		this.y = this.emitter.originY() + relative.y();
		this.z = this.emitter.originZ() + relative.z();

		// A parametric rotation replaces the spin from particle_initial_spin.
		this.parametricRotationDeg = (float) this.effect.compile(parametric.rotation()).eval(this.context);
	}

	/** Bedrock dynamic motion: integrate acceleration and drag in seconds, step by one tick. */
	private void applyDynamicMotion() {
		KashiParticleDefinition.MotionDynamic motion = this.effect.definition().motion();
		double dt = 1.0 / 20.0;

		if (motion != null) {
			Vector3f accel = new Vector3f(
					(float) this.effect.compile(motion.linearAcceleration().x()).eval(this.context),
					(float) this.effect.compile(motion.linearAcceleration().y()).eval(this.context),
					(float) this.effect.compile(motion.linearAcceleration().z()).eval(this.context));

			// Authored in emitter-local axes, same as particle_initial_speed's explicit velocity
			// and motion_parametric's relative_position - has to turn with the same aim that
			// turned those, or an effect that curves "forward" as authored would curve toward
			// world -Z regardless of which way it was actually fired.
			this.emitter.rotateByAim(accel);

			double drag = this.effect.compile(motion.linearDrag()).eval(this.context);

			this.vx += accel.x() * dt;
			this.vy += accel.y() * dt;
			this.vz += accel.z() * dt;

			double keep = Math.max(0, 1 - drag * dt);
			this.vx *= keep;
			this.vy *= keep;
			this.vz *= keep;
		}

		double stepX = this.vx * dt;
		double stepY = this.vy * dt;
		double stepZ = this.vz * dt;

		KashiParticleDefinition.Collision collision = this.effect.definition().collision();

		if (collision != null && this.effect.compile(collision.enabled()).eval(this.context) != 0) {
			collide(collision, stepX, stepY, stepZ, dt);
			return;
		}

		this.x += stepX;
		this.y += stepY;
		this.z += stepZ;
	}

	/**
	 * Moves the particle one step against the world â€” {@code minecraft:particle_motion_collision}.
	 *
	 * <p>Each axis is resolved on its own so a particle sliding along a floor keeps its horizontal
	 * speed instead of stopping dead the moment it lands. On contact the axis' speed is reflected by
	 * the restitution and the others are slowed by the drag, which is what makes a low restitution
	 * read as "settles" rather than "sticks mid-air".
	 */
	private void collide(KashiParticleDefinition.Collision collision,
			double stepX, double stepY, double stepZ, double dt) {
		double radius = collision.radius();
		boolean touched = false;

		if (blocked(this.x + stepX, this.y, this.z, radius)) {
			this.vx = -this.vx * collision.restitution();
			touched = true;
		} else {
			this.x += stepX;
		}

		if (blocked(this.x, this.y + stepY, this.z, radius)) {
			this.vy = -this.vy * collision.restitution();
			touched = true;
		} else {
			this.y += stepY;
		}

		if (blocked(this.x, this.y, this.z + stepZ, radius)) {
			this.vz = -this.vz * collision.restitution();
			touched = true;
		} else {
			this.z += stepZ;
		}

		if (!touched)
			return;

		if (collision.expireOnContact()) {
			expire();
			return;
		}

		double keep = Math.max(0, 1 - collision.drag() * dt);

		this.vx *= keep;
		this.vy *= keep;
		this.vz *= keep;

		this.emitter.fireParticleEvents(collision.events(), this.context, this.x, this.y, this.z);
	}

	/** Whether a sphere of {@code radius} at this point overlaps anything solid. */
	private boolean blocked(double x, double y, double z, double radius) {
		net.minecraft.world.phys.AABB box = new net.minecraft.world.phys.AABB(
				x - radius, y - radius, z - radius, x + radius, y + radius, z + radius);

		// noneMatch over an empty stream is true, so this reads as "nothing solid overlaps".
		return !this.level.noCollision(box);
	}

	/**
	 * The two ways an effect ends a particle by where it is rather than how old it is:
	 * {@code particle_kill_plane} and the {@code expire_if_*_in_blocks} pair.
	 *
	 * @return whether the particle should die now
	 */
	private boolean killedByWorld() {
		KashiParticleDefinition.KillPlane plane = this.effect.definition().killPlane();

		if (plane != null) {
			// The plane is stated in emitter space, so it is measured from the emitter's origin -
			// a plane at the emitter's feet stays at its feet wherever the effect was fired.
			double px = this.x - this.emitter.originX();
			double py = this.y - this.emitter.originY();
			double pz = this.z - this.emitter.originZ();

			if (plane.a() * px + plane.b() * py + plane.c() * pz + plane.d() < 0)
				return true;
		}

		KashiParticleDefinition.BlockFilter filter = this.effect.definition().blockFilter();

		if (!filter.any())
			return false;

		String block = net.minecraft.core.registries.BuiltInRegistries.BLOCK.getKey(
				this.level.getBlockState(net.minecraft.core.BlockPos.containing(this.x, this.y, this.z))
						.getBlock()).toString();

		if (filter.expireInside().contains(block))
			return true;

		return !filter.expireOutside().isEmpty() && !filter.expireOutside().contains(block);
	}

	@Override
	public void render(VertexConsumer buffer, Camera camera, float partialTick) {
		float ageSeconds = (this.age + partialTick) / 20.0f;
		this.context.set(Var.PARTICLE_AGE, ageSeconds);
		// Re-sampled per frame, not per tick: a curve driving size or colour has to move smoothly
		// with the interpolated age or the effect visibly steps at 20 Hz.
		this.effect.applyCurves(this.context);

		// per_render_expression runs before anything is measured, so it can drive size or colour.
		KashiParticleDefinition.ParticleInitialization init = this.effect.definition().particleInit();

		if (init != null)
			this.effect.compile(init.perRender()).eval(this.context);

		float halfW = (float) this.sizeX.eval(this.context);
		float halfH = (float) this.sizeY.eval(this.context);

		float[] rgba = tint(ageSeconds);
		float[] uv = uv(ageSeconds);

		// Measured here rather than at spawn: this is the last point before the quad is written, so
		// whatever is recorded is what the player either saw or did not.
		KashiDiagnostics.drawn(this.effect.definition().identifier(),
				Math.min(Math.abs(halfW), Math.abs(halfH)), rgba[3]);

		Quaternionf facing = facing(camera, partialTick);
		if (this.roll != 0)
			facing.rotateZ(Mth.lerp(partialTick, this.oRoll, this.roll));

		net.minecraft.world.phys.Vec3 cam = camera.getPosition();
		float dx = (float) (Mth.lerp(partialTick, this.xo, this.x) - cam.x());
		float dy = (float) (Mth.lerp(partialTick, this.yo, this.y) - cam.y());
		float dz = (float) (Mth.lerp(partialTick, this.zo, this.z) - cam.z());

		// Bedrock particles are emissive unless the effect asks for world lighting, which is what
		// particle_appearance_lighting means. Without it, full bright matches both Bedrock and how
		// Snowstorm previews the effect.
		int light = this.effect.definition().litByWorld()
				? getLightColor(partialTick) : FULL_BRIGHT;

		// Corner offsets carry width on X and height on Y so non-square sizes render correctly.
		vertex(buffer, facing, dx, dy, dz, halfW, -halfH, uv[2], uv[3], rgba, light);
		vertex(buffer, facing, dx, dy, dz, halfW, halfH, uv[2], uv[1], rgba, light);
		vertex(buffer, facing, dx, dy, dz, -halfW, halfH, uv[0], uv[1], rgba, light);
		vertex(buffer, facing, dx, dy, dz, -halfW, -halfH, uv[0], uv[3], rgba, light);
	}

	private void vertex(VertexConsumer buffer, Quaternionf facing, float cx, float cy, float cz,
			float ox, float oy, float u, float v, float[] rgba, int light) {
		this.vertexScratch.set(ox, oy, 0).rotate(facing).add(cx, cy, cz);

		buffer.addVertex(this.vertexScratch.x(), this.vertexScratch.y(), this.vertexScratch.z())
				.setUv(u, v)
				.setColor(rgba[0], rgba[1], rgba[2], rgba[3])
				.setLight(light);
	}

	/**
	 * How the quad is oriented.
	 *
	 * <p>The {@code emitter_transform_*} modes are <b>not</b> billboards: they pin the quad to a
	 * fixed plane of the emitter, so it can be seen edge-on and vanish - that is the authored
	 * behaviour, not a bug. The quad is built in local XY, so each mode is the rotation that
	 * carries XY onto the requested plane, followed by the emitter's aim.
	 */
	private Quaternionf facing(Camera camera, float partialTick) {
		Quaternionf rotation = camera.rotation();

		return switch (this.effect.definition().appearance().facing()) {
			// Upright billboards: turn to the camera around Y only, so they never tip over.
			case LOOKAT_Y, ROTATE_Y -> this.facingScratch.set(0, rotation.y, 0, rotation.w);

			// Aligned to where the particle is travelling, still turned towards the viewer. This is
			// what makes a slash lie along its own path instead of always squarely facing you.
			case LOOKAT_DIRECTION, DIRECTION_X, DIRECTION_Y, DIRECTION_Z -> directionFacing(rotation);

			// Fixed planes on the emitter's axes - these can be edge-on and vanish, by design.
			case EMITTER_TRANSFORM_XY -> {
				this.emitter.aimRotationInto(this.facingScratch);
				yield this.facingScratch;
			}
			case EMITTER_TRANSFORM_XZ -> {
				this.emitter.aimRotationInto(this.facingScratch);
				yield this.facingScratch.rotateX((float) Math.toRadians(-90));
			}
			case EMITTER_TRANSFORM_YZ -> {
				this.emitter.aimRotationInto(this.facingScratch);
				yield this.facingScratch.rotateY((float) Math.toRadians(90));
			}

			// ROTATE_XYZ and LOOKAT_XYZ: full camera-facing billboard.
			default -> this.facingScratch.set(rotation);
		};
	}

	/**
	 * Orients the quad along the particle's own travel direction, then rolls it to face the viewer
	 * as much as that alignment allows.
	 *
	 * <p>A particle that is not moving has no direction to align to, so it falls back to a plain
	 * camera-facing billboard rather than collapsing to an arbitrary orientation.
	 *
	 * <p>{@code (0,0,-1).rotate(cameraRotation)} is the camera's own forward axis in world space -
	 * the direction it is looking, not the direction back to it - as confirmed by the plain
	 * camera-facing billboard case ({@code new Quaternionf(rotation)} directly, in {@link #facing}):
	 * its normal is {@code (0,0,1).rotate(rotation)}, the exact negation of that forward vector, and
	 * that billboard is known-correct. So a properly viewer-facing normal here has to satisfy
	 * {@code quadNormal Â· cameraForward = -1}, not {@code +1}. The roll computed below aligns
	 * {@code quadNormal} WITH {@code cameraForward} (its atan2 target), so it has to be applied as
	 * {@code roll + Ï€}, not {@code roll} or {@code -roll} - either of those leaves the quad's
	 * normal pointed 180Â° wrong for some or all camera headings, i.e. showing the effect its back
	 * instead of its face. Verified by simulating this exact rotation against all four cardinal
	 * camera headings for a near-vertical travel vector, checked against the known-correct
	 * default-billboard case as the reference: {@code -roll} (the original bug) gives dot â‰ˆ +0.99
	 * for one axis pair and â‰ˆ -0.99 (correct) for the other - matching effects that rendered facing
	 * one pair of directions and vanished facing the other; plain {@code roll} gives â‰ˆ +0.99 for
	 * all four (wrong everywhere); {@code roll + Ï€} gives â‰ˆ -1.0 for all four (correct everywhere).
	 */
	private Quaternionf directionFacing(Quaternionf cameraRotation) {
		this.travelScratch.set((float) this.vx, (float) this.vy, (float) this.vz);

		if (this.travelScratch.lengthSquared() < 1.0e-6f)
			return this.facingScratch.set(cameraRotation);

		this.travelScratch.normalize();

		// The quad is built in local XY, so map its local +X onto the direction of travel; the
		// remaining freedom is spun towards the camera so the face stays readable.
		this.axisScratch.set(1, 0, 0);
		this.facingScratch.identity().rotateTo(this.axisScratch, this.travelScratch);
		this.normalScratch.set(0, 0, 1).rotate(this.facingScratch);
		this.forwardScratch.set(0, 0, -1).rotate(cameraRotation);
		this.crossScratch.set(this.travelScratch).cross(this.normalScratch);

		float roll = (float) Math.atan2(
				this.crossScratch.dot(this.forwardScratch), this.normalScratch.dot(this.forwardScratch));

		return this.facingScratch.rotateX(roll + (float) Math.PI);
	}

	/** Returns {u0, v0, u1, v1} normalised texture coordinates for the current frame. */
	private float[] uv(float ageSeconds) {
		Uv sheet = this.effect.definition().appearance().uv();
		double texW = sheet.textureWidth();
		double texH = sheet.textureHeight();

		if (!sheet.isAnimated())
			return staticUv(sheet, texW, texH);

		Flipbook fb = sheet.flipbook();
		double maxFrame = fb.maxFrame();
		double fps = fb.stretchToLifetime()
				? (this.lifetimeSeconds > 0 ? maxFrame / this.lifetimeSeconds : 0)
				: this.effect.compile(fb.fps()).eval(this.context);

		double animDuration = fps > 0 ? maxFrame / fps : this.lifetimeSeconds;
		double loopTime = fb.loop()
				? (animDuration > 0 ? ageSeconds % animDuration : 0)
				: Math.min(ageSeconds, animDuration);

		int frame = (int) Math.floor(loopTime * fps);
		frame = Mth.clamp(frame, 0, Math.max(0, (int) maxFrame - 1));

		// The UV fields are MoLang; a pack may pick its starting frame from a particle random.
		double baseU = this.effect.compile(fb.baseUv().x()).eval(this.context);
		double baseV = this.effect.compile(fb.baseUv().y()).eval(this.context);
		double stepU = this.effect.compile(fb.stepUv().x()).eval(this.context);
		double stepV = this.effect.compile(fb.stepUv().y()).eval(this.context);
		double sizeU = this.effect.compile(fb.sizeUv().x()).eval(this.context);
		double sizeV = this.effect.compile(fb.sizeUv().y()).eval(this.context);

		this.uvScratch[0] = (float) ((baseU + stepU * frame) / texW);
		this.uvScratch[1] = (float) ((baseV + stepV * frame) / texH);
		this.uvScratch[2] = (float) (this.uvScratch[0] + sizeU / texW);
		this.uvScratch[3] = (float) (this.uvScratch[1] + sizeV / texH);

		return this.uvScratch;
	}

	private float[] staticUv(Uv sheet, double texW, double texH) {
		this.uvScratch[0] = (float) (this.effect.compile(sheet.uv().x()).eval(this.context) / texW);
		this.uvScratch[1] = (float) (this.effect.compile(sheet.uv().y()).eval(this.context) / texH);
		this.uvScratch[2] = (float) (this.uvScratch[0]
				+ this.effect.compile(sheet.uvSize().x()).eval(this.context) / texW);
		this.uvScratch[3] = (float) (this.uvScratch[1]
				+ this.effect.compile(sheet.uvSize().y()).eval(this.context) / texH);

		return this.uvScratch;
	}

	/** Samples the tint gradient at the interpolant, returning premultiplied-free RGBA in 0..1. */
	private float[] tint(float ageSeconds) {
		KashiParticleDefinition.Tinting tinting = this.effect.definition().tinting();

		if (tinting == null)
			return setTintScratch(1, 1, 1, 1);

		if (tinting.color() != null) {
			return setTintScratch(
					(float) this.effect.compile(tinting.color().r()).eval(this.context),
					(float) this.effect.compile(tinting.color().g()).eval(this.context),
					(float) this.effect.compile(tinting.color().b()).eval(this.context),
					(float) this.effect.compile(tinting.color().a()).eval(this.context));
		}

		double interpolant = this.tintInterpolant != null ? this.tintInterpolant.eval(this.context) : 0;

		return sampleGradient(tinting.gradient(), (float) interpolant);
	}

	private float[] sampleGradient(List<GradientStop> stops, float position) {
		if (stops.isEmpty())
			return setTintScratch(1, 1, 1, 1);

		GradientStop first = stops.get(0);
		if (position <= first.position())
			return setTintScratch(first.r(), first.g(), first.b(), first.a());

		for (int i = 1; i < stops.size(); i++) {
			GradientStop hi = stops.get(i);

			if (position <= hi.position()) {
				GradientStop lo = stops.get(i - 1);
				float span = (float) (hi.position() - lo.position());
				float f = span <= 0 ? 0 : (float) ((position - lo.position()) / span);

				return setTintScratch(
						Mth.lerp(f, lo.r(), hi.r()),
						Mth.lerp(f, lo.g(), hi.g()),
						Mth.lerp(f, lo.b(), hi.b()),
						Mth.lerp(f, lo.a(), hi.a()));
			}
		}

		GradientStop last = stops.get(stops.size() - 1);
		return setTintScratch(last.r(), last.g(), last.b(), last.a());
	}

	private float[] setTintScratch(float r, float g, float b, float a) {
		this.tintScratch[0] = r;
		this.tintScratch[1] = g;
		this.tintScratch[2] = b;
		this.tintScratch[3] = a;

		return this.tintScratch;
	}

	/**
	 * The box Minecraft frustum-culls against.
	 *
	 * <p>The inherited box is the particle's tiny collision size, but a KASHI quad is routinely
	 * several blocks across. Left alone, a quad that fills the screen gets culled the moment its
	 * centimetre-sized centre leaves the frustum - which looks like particles jumping around or
	 * vanishing as the camera turns. Sizing the box to the quad fixes that.
	 *
	 * <p>The radius has to be the quad's half-diagonal ({@code sqrt(halfWÂ² + halfHÂ²)}), not just
	 * {@code max(halfW, halfH)} - the quad is rotated (see {@link #facing}), so its farthest
	 * corner from the centre is the diagonal, not an edge midpoint. Using max() under-sizes the
	 * box by up to ~41% on a square quad, which is enough for the frustum test to reject a corner
	 * that is still genuinely on screen - particles would vanish exactly the way this Javadoc
	 * already describes, just from a different cause than the one it fixed.
	 */
	@Override
	public net.minecraft.world.phys.AABB getRenderBoundingBox(float partialTick) {
		double halfW = this.sizeX.eval(this.context);
		double halfH = this.sizeY.eval(this.context);
		double reach = Math.sqrt(halfW * halfW + halfH * halfH);

		return new net.minecraft.world.phys.AABB(
				this.x - reach, this.y - reach, this.z - reach,
				this.x + reach, this.y + reach, this.z + reach);
	}

	@Override
	public void remove() {
		// Free the slot back to the emitter exactly once, so its max_particles cap tracks how many
		// are alive rather than how many were ever spawned.
		if (!this.releasedSlot) {
			this.releasedSlot = true;
			this.emitter.childDied();
		}

		super.remove();
	}

	@Override
	public ParticleRenderType getRenderType() {
		return KashiRenderType.of(this.effect.texture(), this.effect.blend());
	}
}
