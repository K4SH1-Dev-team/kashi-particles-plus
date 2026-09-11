package net.kashi.particles.runtime;

import net.kashi.particles.core.KashiParticleDefinition;
import net.kashi.particles.core.KashiParticleDefinition.EmitterDirection;
import net.kashi.particles.core.KashiParticleDefinition.EmitterLifetime;
import net.kashi.particles.core.KashiParticleDefinition.EmitterRate;
import net.kashi.particles.core.KashiParticleDefinition.EmitterShape;
import net.kashi.particles.core.molang.MolangContext;
import net.kashi.particles.core.molang.MolangContext.Var;

import net.minecraft.client.Camera;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.resources.Identifier;

import org.joml.Quaternionf;
import org.joml.Vector3f;

/**
 * The invisible driver of one KASHI effect instance.
 *
 * <p>A Bedrock particle_effect is an emitter that spawns many particles over its active time. This
 * maps that emitter onto a single, non-rendering Minecraft particle: it lives for the emitter's
 * lifetime, ticks its own clock, and each tick spawns the visible {@link KashiParticle} children
 * the rate calls for, positioned by the emitter shape. Following Wintersky, the emitter's four
 * randoms are drawn once at birth and stay fixed.
 *
 * <p>Shape offsets are authored in emitter-local space; a spawn direction rotates them into world
 * space so a "fired" effect leans the way it was aimed.
 */
public class KashiEmitterParticle extends Particle {

	private final KashiCompiledEffect effect;
	private final MolangContext context;
	private final Quaternionf aim;
	private final double dirX;
	private final double dirY;
	private final double dirZ;

	// --- emitter_local_space: the effect is attached to the entity that fired it ---

	private final KashiParticleDefinition.LocalSpace localSpace;

	/**
	 * Non-empty only for a spawn from the "Attach K4SH1 Particle to Entity" procedure - forces
	 * position AND rotation tracking (yaw and pitch both - see {@link #fullLookFrame}) regardless
	 * of what the source {@code .particle.json} authored in {@link #localSpace}, and picks which
	 * point on the entity {@link #resolveAnchorPosition()} tracks. Empty for every other spawn
	 * path, which is what keeps this feature additive: nothing here changes for an effect that
	 * never opted into being attached.
	 */
	private final String attachPoint;

	/** The entity this effect follows, or null when it is world-space or nothing was named. */
	private final net.minecraft.world.entity.Entity anchor;

	/** Spawn position relative to the anchor, in world axes and in the anchor's yaw frame. */
	private final Vector3f worldOffset = new Vector3f();
	private final Vector3f localOffset = new Vector3f();

	/** The aim expressed in the anchor's yaw frame, so it can be rebuilt as the anchor turns. */
	private final Quaternionf localAim = new Quaternionf();

	private Quaternionf previousFrame = new Quaternionf();

	/** How far the emitter moved and turned during the last tick, for its particles to follow. */
	private double carryX;
	private double carryY;
	private double carryZ;
	private final Quaternionf carryRotation = new Quaternionf();

	/**
	 * Ceiling for emitters that would otherwise run forever (looping, or an expression that never
	 * expires). A KASHI spawn is fire-and-forget - nothing can stop it later - so it is bounded.
	 */
	private static final double MAX_LOOPING_SECONDS = 30;

	private final double activeSeconds;
	private final double sleepSeconds;
	private final int maxParticles;

	/** Additive size offset, threaded through to every particle this emitter spawns. */
	private final float scaleOffset;

	private double spawnAccumulator;

	/** The last emitting cycle an instant rate fired in, so each cycle bursts exactly once. */
	private int lastBurst = -1;

	/** Particles currently alive. Bedrock's max_particles is a concurrent cap, not a total. */
	private int alive;

	// --- events ---

	private final int eventDepth;

	/** How far along the timeline events have already fired, so each fires exactly once. */
	private int timelineFired;

	/** Distance the emitter has travelled, for the travel-distance triggers. */
	private double travelled;
	private int travelFired;
	private double nextLoopingTravel;

	private boolean expirationFired;

	/** Which {@code (effectId, entityId)} to register under for "Stop K4SH1 Particle" - see {@link #remove()}. */
	private final Identifier originEffectId;
	private final int originEntityId;

	KashiEmitterParticle(ClientLevel level, double x, double y, double z, KashiCompiledEffect effect,
			double dirX, double dirY, double dirZ, net.minecraft.world.entity.Entity anchor) {
		this(level, x, y, z, effect, dirX, dirY, dirZ, anchor, 0, 0, 0, "", null, KashiParticleOptions.NO_ENTITY);
	}

	/** @param eventDepth how many chained events deep this emitter already is; 0 when fired directly */
	KashiEmitterParticle(ClientLevel level, double x, double y, double z, KashiCompiledEffect effect,
			double dirX, double dirY, double dirZ, net.minecraft.world.entity.Entity anchor,
			int eventDepth) {
		this(level, x, y, z, effect, dirX, dirY, dirZ, anchor, eventDepth, 0, 0, "",
				null, KashiParticleOptions.NO_ENTITY);
	}

	/**
	 * As the no-offset constructor, with additive scale/duration offsets from the spawn that fired
	 * this effect directly (an event-chained child always gets {@code 0, 0} — see the other
	 * constructor - a hit-effect triggered by a parent effect is its own authored effect, not a
	 * continuation of whatever offset the parent's spawn happened to carry), and an optional
	 * attach point (see {@link #attachPoint}, empty for every spawn except "Attach K4SH1 Particle
	 * to Entity").
	 *
	 * @param originEffectId,originEntityId the {@code (effectId, entityId)} this emitter registers
	 *                                       itself under for "Stop K4SH1 Particle" to find later -
	 *                                       see {@link #remove()}. Always the real spawn packet's
	 *                                       own id/entity here, since this is the constructor
	 *                                       {@code KashiParticleClient} calls directly.
	 */
	KashiEmitterParticle(ClientLevel level, double x, double y, double z, KashiCompiledEffect effect,
			double dirX, double dirY, double dirZ, net.minecraft.world.entity.Entity anchor,
			float scaleOffset, float durationOffset, String attachPoint,
			Identifier originEffectId, int originEntityId) {
		this(level, x, y, z, effect, dirX, dirY, dirZ, anchor, 0, scaleOffset, durationOffset, attachPoint,
				originEffectId, originEntityId);
	}

	/**
	 * @param eventDepth                    how many chained events deep this emitter already is; 0
	 *                                       when fired directly
	 * @param originEffectId,originEntityId see the other constructor's doc comment; {@code null}/
	 *                                       {@link KashiParticleOptions#NO_ENTITY} for an
	 *                                       event-chained child, which is never independently
	 *                                       targetable by Stop (see {@link #remove()}).
	 */
	KashiEmitterParticle(ClientLevel level, double x, double y, double z, KashiCompiledEffect effect,
			double dirX, double dirY, double dirZ, net.minecraft.world.entity.Entity anchor,
			int eventDepth, float scaleOffset, float durationOffset, String attachPoint,
			Identifier originEffectId, int originEntityId) {
		super(level, x, y, z);

		this.scaleOffset = scaleOffset;

		this.eventDepth = eventDepth;

		this.originEffectId = originEffectId;
		this.originEntityId = originEntityId;

		this.attachPoint = attachPoint == null ? "" : attachPoint;

		this.localSpace = effect.definition().localSpace();
		// An effect that never asked to be local, and was not fired through Attach either, ignores
		// the anchor entirely, so passing one can never change an effect that was already correct.
		this.anchor = (this.localSpace.any() || hasAttachPoint()) ? anchor : null;

		this.effect = effect;
		this.context = effect.newContext();
		this.dirX = dirX;
		this.dirY = dirY;
		this.dirZ = dirZ;
		this.aim = aimQuaternion(dirX, dirY, dirZ);

		bindToAnchor(x, y, z);

		KashiParticleDefinition d = effect.definition();

		this.context.set(Var.EMITTER_RANDOM_1, this.random.nextDouble());
		this.context.set(Var.EMITTER_RANDOM_2, this.random.nextDouble());
		this.context.set(Var.EMITTER_RANDOM_3, this.random.nextDouble());
		this.context.set(Var.EMITTER_RANDOM_4, this.random.nextDouble());
		this.context.set(Var.EMITTER_AGE, 0);
		this.effect.applyCurves(this.context);

		// The creation expression runs before anything reads a variable, so an effect that sets up
		// its own variable.* has them defined by the time the shape or rate is first evaluated.
		if (d.emitterInit() != null)
			this.effect.compile(d.emitterInit().creation()).eval(this.context);

		// durationOffset is additive on active_time only - how long the emitter keeps spawning new
		// particles - never on an individual particle's own max_lifetime, per the spawn's contract.
		this.activeSeconds = Math.max(0, emitterActiveTime(d.lifetime()) + durationOffset);
		this.sleepSeconds = emitterSleepTime(d.lifetime());
		this.context.set(Var.EMITTER_LIFETIME, this.activeSeconds);
		// Again now that the emitter's own lifetime is known: a curve is free to use it as its
		// horizontal range, and the first evaluation could not have seen it.
		this.effect.applyCurves(this.context);

		// The base lifetime field only bounds how long this driver can live; isExpired decides when
		// it actually ends, because looping and expression emitters are not a fixed length.
		this.lifetime = Math.max(1, (int) Math.ceil(
				Math.min(MAX_LOOPING_SECONDS, Math.max(this.activeSeconds + this.sleepSeconds,
						this.activeSeconds)) * 20) + 1);
		this.maxParticles = resolveMaxParticles(d.rate());
		this.nextLoopingTravel = d.emitterEvents().travelDistanceLoopingStep();

		fireEvents(d.emitterEvents().creation());

		// Only a directly-spawned emitter has an id to register under - see this field's own doc
		// comment and the constructor javadocs above for why an event-chained child never does.
		if (this.originEffectId != null)
			KashiActiveParticles.track(this.originEffectId, this.originEntityId, this);
	}

	/** Runs named emitter events from this emitter's position, context and aim. */
	private void fireEvents(java.util.List<String> names) {
		KashiEventRunner.fire(this.effect, names, this.context, (ClientLevel) this.level,
				this.x, this.y, this.z, this.dirX, this.dirY, this.dirZ, this.anchor, this.eventDepth);
	}

	/**
	 * Covers every way this emitter can end - natural expiration ({@link #expire()}, which already
	 * calls this), and an external "Stop K4SH1 Particle" force-stop ({@code KashiActiveParticles
	 * #stopMatching} calls this directly). Untracking here rather than only in {@link #expire()}
	 * means both paths - and any future one - stay correctly registered/unregistered with no extra
	 * bookkeeping, the same idempotent-guard shape {@code KashiParticle#remove()} already uses.
	 */
	@Override
	public void remove() {
		if (this.originEffectId != null)
			KashiActiveParticles.untrack(this.originEffectId, this.originEntityId, this);

		super.remove();
	}

	/**
	 * Fires the time- and distance-based triggers that have come due this tick.
	 *
	 * <p>Both lists are sorted, and a cursor walks them: an entry can only fire once, and an
	 * emitter that skipped past several at once (a long tick, or a big jump) still fires them all
	 * rather than losing the ones it overshot.
	 */
	private void fireDueEvents(double ageSeconds) {
		KashiParticleDefinition.LifetimeEvents events = this.effect.definition().emitterEvents();
		java.util.List<KashiParticleDefinition.TimedEvents> timeline = events.timeline();

		while (this.timelineFired < timeline.size()
				&& timeline.get(this.timelineFired).at() <= ageSeconds) {
			fireEvents(timeline.get(this.timelineFired).events());
			this.timelineFired++;
		}

		java.util.List<KashiParticleDefinition.TimedEvents> travel = events.travelDistance();

		while (this.travelFired < travel.size() && travel.get(this.travelFired).at() <= this.travelled) {
			fireEvents(travel.get(this.travelFired).events());
			this.travelFired++;
		}

		// The looping trigger re-arms every 'distance' blocks for as long as the emitter moves.
		double step = events.travelDistanceLoopingStep();

		while (step > 0 && !events.travelDistanceLooping().isEmpty()
				&& this.travelled >= this.nextLoopingTravel) {
			fireEvents(events.travelDistanceLooping());
			this.nextLoopingTravel += step;
		}
	}

	MolangContext context() {
		return this.context;
	}

	// ------------------------------------------------------ emitter_local_space

	/**
	 * Records where the spawn sits relative to its anchor, both ways round.
	 *
	 * <p>Two offsets are kept because {@code position} and {@code rotation} are separate switches:
	 * an effect that follows its entity without turning with it keeps the offset it had in world
	 * axes, while one that also turns keeps it in the entity's frame so it swings around as the
	 * entity looks elsewhere.
	 */
	private void bindToAnchor(double x, double y, double z) {
		if (this.anchor == null)
			return;

		net.minecraft.world.phys.Vec3 point = resolveAnchorPosition();

		this.worldOffset.set((float) (x - point.x), (float) (y - point.y), (float) (z - point.z));
		this.previousFrame = followFrame(this.anchor);

		Quaternionf inverse = new Quaternionf(this.previousFrame).conjugate();

		inverse.transform(this.localOffset.set(this.worldOffset));
		inverse.mul(this.aim, this.localAim);
	}

	private boolean hasAttachPoint() {
		return !this.attachPoint.isEmpty();
	}

	/**
	 * The world position {@link #bindToAnchor}/{@link #followAnchor} track this tick - delegates to
	 * {@link KashiParticleAPI#resolveAttachPoint} so this class and the initial spawn-origin
	 * computation for "Attach K4SH1 Particle to Entity" (which can run server-side, so cannot call
	 * back into this client-only class) never disagree about where a named point actually is.
	 */
	private net.minecraft.world.phys.Vec3 resolveAnchorPosition() {
		return KashiParticleAPI.resolveAttachPoint(this.anchor, this.attachPoint);
	}

	/**
	 * The anchor's heading as a rotation, yaw only.
	 *
	 * <p>Deliberately not the full look direction: binding to pitch as well would make a effect
	 * fired while looking level tip over the moment the player glanced up, which is not what
	 * "follows the entity" means to anyone authoring one. This is what {@code
	 * minecraft:emitter_local_space}'s own {@code rotation} switch has always used, and still does
	 * - {@link #followFrame} is what changed, not this method.
	 */
	private static Quaternionf yawFrame(net.minecraft.world.entity.Entity entity) {
		net.minecraft.world.phys.Vec3 look = entity.getLookAngle();

		if (look.x * look.x + look.z * look.z < 1.0e-8)
			return new Quaternionf();

		return new Quaternionf().rotateY((float) Math.atan2(-look.x, -look.z));
	}

	/**
	 * The anchor's heading as a rotation, yaw AND pitch - reuses {@link #aimQuaternion} against the
	 * anchor's own look direction rather than re-deriving the same yaw/pitch decomposition. Used
	 * only for Attach ({@link #hasAttachPoint()}): a HEAD or EYE point turning to look up or down is
	 * exactly what an attached effect should follow, unlike a plain {@code emitter_local_space}
	 * effect, which keeps the yaw-only behaviour {@link #yawFrame} always had (see its own doc
	 * comment for why pitch is deliberately excluded there).
	 */
	private static Quaternionf fullLookFrame(net.minecraft.world.entity.Entity entity) {
		net.minecraft.world.phys.Vec3 look = entity.getLookAngle();

		return aimQuaternion(look.x, look.y, look.z);
	}

	/**
	 * Which heading {@link #bindToAnchor}/{@link #followAnchor} track - see {@link #fullLookFrame}.
	 * For a hand/foot attach point, tilts the look-based frame a bit further by
	 * {@link KashiParticleAPI#resolveLimbSwingRadians}, so an effect attached there turns as the
	 * limb swings (a punch, a walking stride) rather than only ever turning with the entity's own
	 * look direction. {@code rotateX} post-multiplies, the same convention {@link #aimQuaternion}
	 * already uses for yaw-then-pitch, so the limb tilt is applied in the frame already oriented by
	 * the entity's look, not around a world-absolute axis. Every other attach point (and every
	 * non-Attach spawn) gets {@code 0} back from {@code resolveLimbSwingRadians}, so this is a
	 * no-op for them.
	 */
	private Quaternionf followFrame(net.minecraft.world.entity.Entity entity) {
		if (!hasAttachPoint())
			return yawFrame(entity);
		float limbSwing = KashiParticleAPI.resolveLimbSwingRadians(entity, this.attachPoint);
		Quaternionf frame = fullLookFrame(entity);
		return limbSwing == 0 ? frame : frame.rotateX(limbSwing);
	}

	/**
	 * Moves the emitter to wherever its anchor is now, and records the move so its particles can
	 * make the same one.
	 */
	private void followAnchor() {
		this.carryX = 0;
		this.carryY = 0;
		this.carryZ = 0;
		this.carryRotation.identity();

		if (this.anchor == null || !this.anchor.isAlive())
			return;

		Quaternionf frame = followFrame(this.anchor);

		// Attach forces rotation tracking too, on top of position - see followFrame()/
		// resolveAnchorPosition()'s doc comments. Velocity inheritance stays driven by localSpace
		// alone, untouched by attachPoint, on purpose.
		if (this.localSpace.rotation() || hasAttachPoint()) {
			// The turn since last tick, in world axes: what every particle has to be swung by.
			new Quaternionf(this.previousFrame).conjugate().premul(frame, this.carryRotation);

			frame.transform(this.localOffset, this.worldOffset);
			frame.mul(this.localAim, this.aim);
		}

		this.previousFrame = frame;

		// Attach forces position tracking too, regardless of what the source effect authored - see
		// resolveAnchorPosition()'s doc comment. Velocity inheritance is the one thing that stays
		// driven by localSpace alone, untouched by attachPoint, on purpose.
		if (!this.localSpace.position() && !hasAttachPoint())
			return;

		net.minecraft.world.phys.Vec3 point = resolveAnchorPosition();

		double targetX = point.x + this.worldOffset.x();
		double targetY = point.y + this.worldOffset.y();
		double targetZ = point.z + this.worldOffset.z();

		this.carryX = targetX - this.x;
		this.carryY = targetY - this.y;
		this.carryZ = targetZ - this.z;

		// Travel distance is what the emitter has actually covered, which only a bound emitter ever
		// does - a fired effect stays put and its distance triggers never come due.
		this.travelled += Math.sqrt(this.carryX * this.carryX + this.carryY * this.carryY
				+ this.carryZ * this.carryZ);

		this.setPos(targetX, targetY, targetZ);
	}

	/** The entity this effect follows, passed on to effects it spawns so a bound child follows too. */
	net.minecraft.world.entity.Entity anchor() {
		return this.anchor;
	}

	int eventDepth() {
		return this.eventDepth;
	}

	/** Runs named particle events, on behalf of one of this emitter's particles. */
	void fireParticleEvents(java.util.List<String> names, MolangContext particleContext,
			double x, double y, double z) {
		KashiEventRunner.fire(this.effect, names, particleContext, (ClientLevel) this.level,
				x, y, z, this.dirX, this.dirY, this.dirZ, this.anchor, this.eventDepth);
	}

	/** How far the emitter moved during the last tick; zero unless it is following an entity. */
	double carryX() {
		return this.carryX;
	}

	double carryY() {
		return this.carryY;
	}

	double carryZ() {
		return this.carryZ;
	}

	/** The turn the emitter made during the last tick, identity unless its rotation is local. */
	Quaternionf carryRotation() {
		return this.carryRotation;
	}

	boolean carriesParticles() {
		return this.anchor != null && (this.localSpace.position() || hasAttachPoint());
	}

	boolean turnsParticles() {
		return this.anchor != null && (this.localSpace.rotation() || hasAttachPoint());
	}

	/**
	 * The anchor's own motion, which particles are born already carrying when the effect declares
	 * {@code local_space.velocity}.
	 */
	net.minecraft.world.phys.Vec3 inheritedVelocity() {
		if (this.anchor == null || !this.localSpace.velocity())
			return net.minecraft.world.phys.Vec3.ZERO;

		// Per tick in Minecraft, per second in Bedrock - the particle integrates in seconds.
		return this.anchor.getDeltaMovement().scale(20);
	}

	// Parametric motion positions particles relative to their emitter, so it needs the origin and
	// the same aim rotation the spawn used.

	double originX() {
		return this.x;
	}

	double originY() {
		return this.y;
	}

	double originZ() {
		return this.z;
	}

	void rotateByAim(Vector3f local) {
		local.rotate(this.aim);
	}

	/**
	 * Writes the aim rotation into {@code dest}, for the emitter_transform_* billboard modes.
	 *
	 * <p>Takes a destination instead of returning a fresh copy: the caller renders every frame for
	 * every particle under this emitter, so allocating here would be one more small object per
	 * particle per frame - the caller passes its own reusable scratch quaternion instead.
	 */
	void aimRotationInto(Quaternionf dest) {
		dest.set(this.aim);
	}

	@Override
	public void tick() {
		this.age++;

		// Before anything spawns, so a new particle is born at where the anchor is now rather than
		// where it was when the effect was fired.
		followAnchor();

		double ageSeconds = this.age / 20.0;
		this.context.set(Var.EMITTER_AGE, ageSeconds);
		this.effect.applyCurves(this.context);

		// Per-update runs before the lifetime checks, so a variable it drives can be what the
		// expiration expression tests against this same tick.
		KashiParticleDefinition.EmitterInitialization init = this.effect.definition().emitterInit();

		if (init != null)
			this.effect.compile(init.perUpdate()).eval(this.context);

		fireDueEvents(ageSeconds);

		if (isExpired(ageSeconds)) {
			expire();
			return;
		}

		if (isEmitting(ageSeconds))
			emit(ageSeconds);
	}

	/**
	 * Ends the emitter, firing its expiration events on the way out.
	 *
	 * <p>Guarded because an expiration event that spawns another effect at this position is the
	 * usual way a chained effect is built, and firing it twice would double every chain.
	 */
	private void expire() {
		if (!this.expirationFired) {
			this.expirationFired = true;

			fireEvents(this.effect.definition().emitterEvents().expiration());
		}

		this.remove();
	}

	/** Which emitting cycle {@code ageSeconds} falls in. Always 0 for a one-shot emitter. */
	private int burstCycle(double ageSeconds) {
		if (!(this.effect.definition().lifetime() instanceof EmitterLifetime.Looping))
			return 0;

		double cycle = this.activeSeconds + this.sleepSeconds;

		return cycle <= 0 ? 0 : (int) Math.floor(ageSeconds / cycle);
	}

	private void emit(double ageSeconds) {
		EmitterRate rate = this.effect.definition().rate();

		if (rate instanceof EmitterRate.Steady steady) {
			double perSecond = this.effect.compile(steady.spawnRate()).eval(this.context);

			this.spawnAccumulator += perSecond / 20.0;

			while (this.spawnAccumulator >= 1) {
				this.spawnAccumulator -= 1;
				spawnOne();
			}
		} else if (rate instanceof EmitterRate.Instant instant) {
			// One burst per emitting cycle, not one burst ever: an instant rate under a looping
			// emitter re-fires every time the loop comes back round, which is how the pack builds
			// a repeating spark out of a single particle. Keying off the cycle rather than off
			// age == 1 also survives an emitter whose first tick is not its first emitting tick.
			int cycle = burstCycle(ageSeconds);

			if (cycle != this.lastBurst) {
				this.lastBurst = cycle;

				int count = (int) this.effect.compile(instant.numParticles()).eval(this.context);

				for (int i = 0; i < count; i++)
					spawnOne();
			}
		}
		// Manual rate emits only on explicit request, which the debug path does not drive.
	}

	private void spawnOne() {
		// max_particles caps how many are alive at once, so a steady emitter keeps topping the
		// effect up as older particles expire rather than stopping forever at the first N.
		if (this.alive >= this.maxParticles)
			return;

		this.alive++;

		KashiDiagnostics.spawned(this.effect.definition().identifier());

		// The new particle's four randoms are rolled BEFORE the shape is evaluated, and the shape
		// expressions are evaluated against the particle's own context. Bedrock effects routinely
		// place particles with variable.particle_random_*, so evaluating the offset in the
		// emitter's context (where those are still 0) would stack every particle on one spot.
		// Handing the same context to the particle also keeps a random consistent between the
		// position that used it and, say, the size expression that uses it again.
		MolangContext spawnContext = this.effect.newContext();

		spawnContext.inheritEmitterState(this.context);
		// Variables the emitter declared for itself are readable by its particles.
		spawnContext.copyCustomFrom(this.context);
		spawnContext.set(Var.PARTICLE_RANDOM_1, this.random.nextDouble());
		spawnContext.set(Var.PARTICLE_RANDOM_2, this.random.nextDouble());
		spawnContext.set(Var.PARTICLE_RANDOM_3, this.random.nextDouble());
		spawnContext.set(Var.PARTICLE_RANDOM_4, this.random.nextDouble());
		spawnContext.set(Var.PARTICLE_AGE, 0);
		// Curves resolve before the shape is evaluated, so an offset driven by a curve spawns the
		// particle where the curve says rather than at the origin.
		this.effect.applyCurves(spawnContext);

		// The spawn point is the shape's base offset plus a point picked within the shape; the
		// "outwards" direction is the radial part alone, measured from the shape centre - the base
		// offset only translates the whole shape and must not tilt the launch direction.
		Vector3f base = baseOffset(spawnContext);
		Vector3f radial = radialPoint(spawnContext);

		Vector3f local = new Vector3f(base).add(radial);
		Vector3f world = local.rotate(this.aim);

		double px = this.x + world.x();
		double py = this.y + world.y();
		double pz = this.z + world.z();

		Vector3f dir = spawnDirection(spawnContext, radial);

		KashiParticle particle = new KashiParticle((ClientLevel) this.level, px, py, pz, this,
				this.effect, spawnContext, dir.x(), dir.y(), dir.z(), this.scaleOffset);

		Minecraft.getInstance().particleEngine.add(particle);
	}

	/** The shape's base translation in emitter-local space, for the particle being spawned. */
	private Vector3f baseOffset(MolangContext spawnContext) {
		EmitterShape shape = this.effect.definition().shape();

		return new Vector3f(
				(float) this.effect.compile(shape.offset().x()).eval(spawnContext),
				(float) this.effect.compile(shape.offset().y()).eval(spawnContext),
				(float) this.effect.compile(shape.offset().z()).eval(spawnContext));
	}

	/** A point picked within (or on) the shape, relative to its centre - the radial component. */
	private Vector3f radialPoint(MolangContext spawnContext) {
		EmitterShape shape = this.effect.definition().shape();

		if (shape instanceof EmitterShape.Sphere sphere) {
			double radius = this.effect.compile(sphere.radius()).eval(spawnContext);
			// surface_only puts every particle on the shell; otherwise fill the volume evenly
			// (cube-root keeps the distribution uniform rather than clumped at the centre).
			double r = sphere.surfaceOnly() ? radius : radius * Math.cbrt(this.random.nextDouble());

			return randomUnitVector().mul((float) r);
		}

		if (shape instanceof EmitterShape.Box box) {
			double hx = this.effect.compile(box.halfDimensions().x()).eval(spawnContext);
			double hy = this.effect.compile(box.halfDimensions().y()).eval(spawnContext);
			double hz = this.effect.compile(box.halfDimensions().z()).eval(spawnContext);

			return new Vector3f(
					(float) ((this.random.nextDouble() * 2 - 1) * hx),
					(float) ((this.random.nextDouble() * 2 - 1) * hy),
					(float) ((this.random.nextDouble() * 2 - 1) * hz));
		}

		if (shape instanceof EmitterShape.Disc disc) {
			double radius = this.effect.compile(disc.radius()).eval(spawnContext);
			// sqrt keeps a filled disc evenly covered; without it particles bunch at the centre.
			double r = disc.surfaceOnly() ? radius : radius * Math.sqrt(this.random.nextDouble());
			double angle = this.random.nextDouble() * Math.PI * 2;

			Vector3f normal = new Vector3f(
					(float) this.effect.compile(disc.planeNormal().x()).eval(spawnContext),
					(float) this.effect.compile(disc.planeNormal().y()).eval(spawnContext),
					(float) this.effect.compile(disc.planeNormal().z()).eval(spawnContext));

			if (normal.lengthSquared() < 1.0e-6f)
				normal.set(0, 1, 0);

			normal.normalize();

			// Any two axes perpendicular to the normal span the disc's plane. Pick the world axis
			// least aligned with the normal so the cross product never degenerates.
			Vector3f helper = Math.abs(normal.y()) > 0.9f ? new Vector3f(1, 0, 0) : new Vector3f(0, 1, 0);
			Vector3f across = new Vector3f(normal).cross(helper).normalize();
			Vector3f along = new Vector3f(normal).cross(across).normalize();

			return across.mul((float) (Math.cos(angle) * r))
					.add(along.mul((float) (Math.sin(angle) * r)));
		}

		if (shape instanceof EmitterShape.EntityAabb) {
			// Bedrock fills the emitting entity's bounding box. A KASHI spawn is not attached to an
			// entity, so we approximate a player-sized box around the spawn point.
			return new Vector3f(
					(float) ((this.random.nextDouble() * 2 - 1) * 0.4),
					(float) ((this.random.nextDouble() * 2 - 1) * 0.9),
					(float) ((this.random.nextDouble() * 2 - 1) * 0.4));
		}

		return new Vector3f();
	}

	/** The particle's launch direction in emitter-local space, before the aim rotation. */
	private Vector3f spawnDirection(MolangContext spawnContext, Vector3f radial) {
		EmitterDirection direction = shapeDirection();
		Vector3f local;

		if (direction instanceof EmitterDirection.Custom custom) {
			local = new Vector3f(
					(float) this.effect.compile(custom.vector().x()).eval(spawnContext),
					(float) this.effect.compile(custom.vector().y()).eval(spawnContext),
					(float) this.effect.compile(custom.vector().z()).eval(spawnContext));
		} else {
			// Outwards is the radial direction from the shape centre; inwards flips it.
			boolean inwards = direction instanceof EmitterDirection.Relative relative
					&& relative.mode() == EmitterDirection.Mode.INWARDS;
			local = new Vector3f(radial);

			if (inwards)
				local.negate();
		}

		if (local.lengthSquared() < 1.0e-6f)
			local.set(0, 1, 0);

		local.normalize().rotate(this.aim);

		return local;
	}

	private EmitterDirection shapeDirection() {
		return switch (this.effect.definition().shape()) {
			case EmitterShape.Point point -> point.direction();
			case EmitterShape.Sphere sphere -> sphere.direction();
			case EmitterShape.Box box -> box.direction();
			case EmitterShape.Disc disc -> disc.direction();
			case EmitterShape.EntityAabb aabb -> aabb.direction();
		};
	}

	private Vector3f randomUnitVector() {
		// Uniform on the sphere via normalised Gaussians.
		float x = (float) this.random.nextGaussian();
		float y = (float) this.random.nextGaussian();
		float z = (float) this.random.nextGaussian();
		Vector3f v = new Vector3f(x, y, z);

		return v.lengthSquared() < 1.0e-6f ? new Vector3f(0, 1, 0) : v.normalize();
	}

	/** One child died; free its slot so a steady emitter can top the effect back up. */
	void childDied() {
		if (this.alive > 0)
			this.alive--;
	}

	/**
	 * Whether the emitter is inside an emitting phase right now.
	 *
	 * <p>{@code once} emits for its active time. {@code looping} alternates active and sleep
	 * phases forever. {@code expression} emits while its activation expression is non-zero.
	 */
	private boolean isEmitting(double ageSeconds) {
		return switch (this.effect.definition().lifetime()) {
			case EmitterLifetime.Once once -> ageSeconds <= this.activeSeconds;
			case EmitterLifetime.Looping looping -> {
				double cycle = this.activeSeconds + this.sleepSeconds;

				yield cycle <= 0 || (ageSeconds % cycle) < this.activeSeconds;
			}
			case EmitterLifetime.Expression expression ->
					this.effect.compile(expression.activation()).eval(this.context) != 0;
		};
	}

	/** Whether the emitter has finished for good and should be removed. */
	private boolean isExpired(double ageSeconds) {
		return switch (this.effect.definition().lifetime()) {
			case EmitterLifetime.Once once -> ageSeconds > this.activeSeconds;
			// A looping emitter never ends on its own. A KASHI spawn is fire-and-forget, with no
			// handle to stop it later, so it is capped instead of leaking an immortal emitter.
			case EmitterLifetime.Looping looping -> ageSeconds > MAX_LOOPING_SECONDS;
			case EmitterLifetime.Expression expression ->
					this.effect.compile(expression.expiration()).eval(this.context) != 0
							|| ageSeconds > MAX_LOOPING_SECONDS;
		};
	}

	/** The active time of one emitting phase, evaluated against the emitter's own context. */
	private double emitterActiveTime(EmitterLifetime lifetime) {
		return switch (lifetime) {
			case EmitterLifetime.Once once -> this.effect.compile(once.activeTime()).eval(this.context);
			case EmitterLifetime.Looping looping -> this.effect.compile(looping.activeTime()).eval(this.context);
			// An expression-driven emitter has no fixed active time; it is asked every tick.
			case EmitterLifetime.Expression expression -> MAX_LOOPING_SECONDS;
		};
	}

	private double emitterSleepTime(EmitterLifetime lifetime) {
		return lifetime instanceof EmitterLifetime.Looping looping
				? this.effect.compile(looping.sleepTime()).eval(this.context) : 0;
	}

	private int resolveMaxParticles(EmitterRate rate) {
		double max = switch (rate) {
			case EmitterRate.Steady steady -> this.effect.compile(steady.maxParticles()).eval(this.context);
			case EmitterRate.Instant instant -> this.effect.compile(instant.numParticles()).eval(this.context);
			case EmitterRate.Manual manual -> this.effect.compile(manual.maxParticles()).eval(this.context);
		};

		return Math.max(1, (int) max);
	}

	/**
	 * Builds the rotation that aims the effect along a direction.
	 *
	 * <p>A Bedrock effect's authored "forward" is <b>-Z</b> (the direction its offsets and motion
	 * travel), so aiming maps -Z onto the requested direction. Mapping the wrong axis — e.g. +Y —
	 * tips the whole effect on its side, throwing particles out of view. A zero direction means
	 * "no aim": the effect plays in its natural orientation, exactly as authored in Snowstorm.
	 */
	private static Quaternionf aimQuaternion(double dx, double dy, double dz) {
		Vector3f aim = new Vector3f((float) dx, (float) dy, (float) dz);

		if (aim.lengthSquared() < 1.0e-6f)
			return new Quaternionf();

		aim.normalize();

		// Decompose into yaw then pitch, the same way Minecraft orients an entity. A shortest-arc
		// rotation (rotateTo) would reach the same direction but with an arbitrary roll around it,
		// which visibly tumbles the effect as soon as the aim has any pitch - "up" must stay up.
		float yaw = (float) Math.atan2(-aim.x(), -aim.z());
		float pitch = (float) Math.asin(Math.max(-1, Math.min(1, aim.y())));

		return new Quaternionf().rotateY(yaw).rotateX(pitch);
	}

	// No render()/extractQuad() override: the emitter itself draws nothing, only its children are
	// visible, and unlike 1.21.1/1.21.8, Particle no longer declares a render(VertexConsumer, ...)
	// method at all for a NO_RENDER particle to no-op - there is simply nothing to override here
	// any more (confirmed against the real 26.1.2 Particle/NoRenderParticle source).

	@Override
	public ParticleRenderType getGroup() {
		return ParticleRenderType.NO_RENDER;
	}
}
