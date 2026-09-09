package net.kashi.particles.runtime;

import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;

/**
 * The one entry point procedures call to fire a KASHI effect.
 *
 * <p>Everything about the effect — duration, motion, animation, colour — comes from the imported
 * {@code .particle.json}. A spawn only says which effect, where, and (optionally) which way it is
 * aimed; it configures nothing.
 *
 * <p>This is the NeoForge 1.21.8 variant of this file (see {@code runtime-1.21.8/} and
 * {@code tools/make-runtime-templates.ps1}) — identical to the 1.21.1 one except for the
 * {@link ServerLevel#sendParticles} call, whose signature gained an extra boolean parameter
 * between 1.21.1 and 1.21.8 (confirmed against the real 1.21.8 source: {@code longDistance} was
 * renamed {@code overrideLimiter} - same role, same 32-vs-512-block radius - and a new
 * {@code alwaysShow} flag was added alongside it, which this passes as {@code false} to keep
 * behaviour identical to the 1.21.1 build).
 */
public final class KashiParticleAPI {

	private KashiParticleAPI() {
	}

	/**
	 * Fires a KASHI effect at a world position, aimed along a direction.
	 *
	 * @param dirX,dirY,dirZ the aim direction; pass {@code (0,0,0)} for an unaimed spawn
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ) {
		spawnKashiParticle(level, effectId, x, y, z, dirX, dirY, dirZ,
				KashiParticleOptions.NO_ENTITY, 0, 0);
	}

	/**
	 * As above, but naming the entity the spawn came from.
	 *
	 * <p>The entity is only used by effects that declare {@code minecraft:emitter_local_space}:
	 * those follow it instead of staying where they were fired. Every other effect ignores it, so
	 * passing an entity never changes an effect that did not ask to be attached.
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ, int entityId) {
		spawnKashiParticle(level, effectId, x, y, z, dirX, dirY, dirZ, entityId, 0, 0);
	}

	/**
	 * As the no-entity overload, with additive scale/duration offsets on top of what the effect
	 * authored in Snowstorm.
	 *
	 * @param scaleOffset    added to every particle's authored half-width/half-height, floored at
	 *                       0; {@code 0} leaves the authored size untouched
	 * @param durationOffset added to the emitter's {@code active_time} (how long it keeps spawning
	 *                       new particles), not to any individual particle's lifetime; {@code 0}
	 *                       leaves it untouched
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ,
			float scaleOffset, float durationOffset) {
		spawnKashiParticle(level, effectId, x, y, z, dirX, dirY, dirZ,
				KashiParticleOptions.NO_ENTITY, scaleOffset, durationOffset);
	}

	/**
	 * The real implementation: names the entity the spawn came from and applies additive
	 * scale/duration offsets. Every other overload delegates here.
	 *
	 * <p>On the server, {@link Level#addParticle} is a no-op — its body is empty on {@code Level}
	 * and {@code ServerLevel} does not override it, so calling it server-side never reaches a
	 * client. {@link ServerLevel#sendParticles} is the real broadcast, and passing
	 * {@code overrideLimiter = true} widens the broadcast radius from 32 to 512 blocks (the same
	 * role {@code longDistance} played in 1.21.1, renamed here), so a distant effect that is
	 * genuinely in view still arrives. {@code alwaysShow = false} keeps the client-side particle
	 * limiter/graphics-setting behaviour identical to the 1.21.1 build - this plugin already
	 * forces every KASHI particle type to override that limiter at the type level (see
	 * {@link KashiParticleType}), so this flag adds nothing beyond what already happens. On the
	 * client, {@code addParticle} spawns locally as before.
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ, int entityId,
			float scaleOffset, float durationOffset) {
		spawnKashiParticle(level, effectId, x, y, z, dirX, dirY, dirZ, entityId,
				scaleOffset, durationOffset, "");
	}

	/**
	 * The real implementation, with an attach point on top of everything the other overload
	 * takes. Every other overload delegates here (through the one above).
	 *
	 * @param attachPoint which point on {@code entityId} the spawn should keep tracking every
	 *                     tick - empty for a one-shot spawn, non-empty only from "Attach K4SH1
	 *                     Particle to Entity" (see {@code KashiParticleAPI#attachToEntity}); see
	 *                     {@code KashiEmitterParticle#resolveAnchorPosition()} for the values it
	 *                     understands
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ, int entityId,
			float scaleOffset, float durationOffset, String attachPoint) {
		ParticleOptions options = new KashiParticleOptions(effectId,
				(float) dirX, (float) dirY, (float) dirZ, entityId,
				new KashiParticleOptions.Extras(scaleOffset, durationOffset, attachPoint));

		if (level instanceof ServerLevel serverLevel) {
			for (ServerPlayer player : serverLevel.players())
				serverLevel.sendParticles(player, options, true, false, x, y, z, 0, 0, 0, 0, 0);
		} else {
			// The emitter particle is created client-side by the registered provider.
			level.addParticle(options, x, y, z, 0, 0, 0);
		}
	}

	/** How the whole effect is turned in the world when an entity fires it. */
	public static final String AIM_NONE = "NONE";
	public static final String AIM_HORIZONTAL = "HORIZONTAL";
	public static final String AIM_FULL = "FULL";

	/**
	 * Fires an effect from an entity, offset from its feet and turned according to an aim mode.
	 *
	 * <p>Aim and the effect's own {@code facing_camera_mode} are different things and both matter.
	 * Facing decides how each particle is oriented (set in Snowstorm, per effect); aim decides how
	 * the effect as a whole is rotated in the world:
	 *
	 * <ul>
	 * <li>{@link #AIM_NONE} — world orientation, up stays up. What AOE effects need, and what makes
	 *     an {@code emitter_transform_*} effect readable instead of edge-on.</li>
	 * <li>{@link #AIM_HORIZONTAL} — turns with the entity but never tilts, so looking up or down
	 *     does not send the effect up or down.</li>
	 * <li>{@link #AIM_FULL} — follows the whole look direction, pitch included.</li>
	 * </ul>
	 *
	 * <p>The offset is measured in the entity's own frame - {@code forward} is where it is facing
	 * horizontally, so "3 blocks in front" stays 3 blocks in front whether it looks up or down.
	 * {@code up} is measured from the entity's feet (its base position, not its eyes), so
	 * {@code up: 0} lands the effect on the ground under the entity - the common case for auras
	 * and area effects - rather than requiring a negative offset to compensate for eye height.
	 * Aim direction still comes from {@link Entity#getLookAngle()}, independent of this anchor.
	 *
	 * @param scaleOffset,durationOffset additive offsets on top of what the effect authored; see
	 *                                   {@link #spawnKashiParticle(Level, ResourceLocation, double,
	 *                                   double, double, double, double, double, int, float, float)}
	 */
	public static void spawnFromEntity(Level level, ResourceLocation effectId, Entity entity,
			double right, double up, double forward, String aimMode,
			float scaleOffset, float durationOffset) {
		if (entity == null)
			return;

		Vec3 origin = entityFrameOffset(entity, entity.position(), right, up, forward);
		Vec3 aim = aimVector(entity, aimMode);

		spawnKashiParticle(level, effectId, origin.x, origin.y, origin.z, aim.x, aim.y, aim.z,
				entity.getId(), scaleOffset, durationOffset);
	}

	/**
	 * Fires an effect that keeps following an entity every tick, anchored at a point on it, instead
	 * of spawning once at a fixed position - an aura, fire on the feet, energy in a hand.
	 *
	 * <p>The offset and aim work like {@link #spawnFromEntity}, except {@code right}/{@code up}/
	 * {@code forward} are measured from {@code attachPoint} itself (see {@link #resolveAttachPoint})
	 * rather than always the entity's feet - {@code up: 0} lands the effect exactly on the chosen
	 * point, matching what {@code KashiEmitterParticle} then keeps tracking every tick from there
	 * on, rather than only reading the entity's position once at fire time - see
	 * {@code KashiEmitterParticle#resolveAnchorPosition()} for the tracking mechanism itself, which
	 * calls this same {@link #resolveAttachPoint} so the two never disagree about where a point is.
	 *
	 * <p>Only position is forced to follow. An offset does not swing around as the entity turns
	 * unless the effect being fired separately authors {@code minecraft:emitter_local_space}'s
	 * {@code rotation} switch itself - deliberate, not an oversight: most of what this is for (an
	 * aura or fire at zero offset, energy roughly centred on a hand) does not need it.
	 *
	 * <p>Like every KASHI spawn, this is still bounded by the emitter's own fire-and-forget lifetime
	 * cap - an attached looping effect still ends on its own after at most 30 seconds, even though
	 * it kept following the entity right up until then. There is no way to attach one that runs
	 * until the entity itself does something to end it; that needs a way to name and later stop a
	 * running instance, which this does not provide.
	 *
	 * @param attachPoint {@code "ROOT"} (root/body), {@code "HEAD"} or {@code "EYE"} for the
	 *                    low-effort anchors this overload is for today - see
	 *                    {@code KashiEmitterParticle#resolveAnchorPosition()} for the full list as
	 *                    it grows
	 */
	public static void attachToEntity(Level level, ResourceLocation effectId, Entity entity,
			double right, double up, double forward, String aimMode, String attachPoint,
			float scaleOffset, float durationOffset) {
		if (entity == null || attachPoint == null || attachPoint.isEmpty())
			return;

		Vec3 base = resolveAttachPoint(entity, attachPoint);
		Vec3 origin = entityFrameOffset(entity, base, right, up, forward);
		Vec3 aim = aimVector(entity, aimMode);

		spawnKashiParticle(level, effectId, origin.x, origin.y, origin.z, aim.x, aim.y, aim.z,
				entity.getId(), scaleOffset, durationOffset, attachPoint);
	}

	/**
	 * The world position on {@code entity} that an attach point names - the single source of truth
	 * both {@link #attachToEntity} (the initial spawn origin, which may run server-side) and {@code
	 * KashiEmitterParticle} (the per-tick follow, client-only) call, so the two never disagree about
	 * where "ROOT"/"HEAD"/"EYE" actually is - a mismatch there would make the effect's fine offset,
	 * captured once at spawn as the gap to the anchor, cancel the chosen point out on the very next
	 * tick instead of tracking it.
	 *
	 * <p>{@code ""} (every spawn except Attach) and {@code "EYE"} both resolve to {@link
	 * Entity#getEyePosition()} - the same point {@code emitter_local_space} alone always tracked
	 * before this method existed, so an effect using it on its own is unaffected. {@code "ROOT"}
	 * covers both "root" and "body" from the Attach dropdown - no meaningful difference for a
	 * generic {@link Entity}. {@code "HEAD"} is a plain fraction of the entity's own bounding-box
	 * height, not a real head-bone lookup - a documented approximation, tuned against what actually
	 * looks right in-game rather than derived.
	 */
	public static Vec3 resolveAttachPoint(Entity entity, String attachPoint) {
		return switch (attachPoint) {
			case "ROOT" -> entity.position();
			case "HEAD" -> entity.position().add(0, entity.getBbHeight() * 0.9, 0);
			default -> entity.getEyePosition(); // "" (legacy) and "EYE" both land here
		};
	}

	/**
	 * A world point offset from {@code base} in the entity's own frame - {@code forward} is where
	 * it is facing horizontally, {@code right} across that, {@code up} straight from {@code base}.
	 * Shared by {@link #spawnFromEntity} (which always passes {@code entity.position()}, its feet)
	 * and {@link #attachToEntity} (which passes {@link #resolveAttachPoint}'s result instead), so
	 * the two agree on what an offset means once the base point itself is settled.
	 */
	private static Vec3 entityFrameOffset(Entity entity, Vec3 base, double right, double up, double forward) {
		Vec3 look = entity.getLookAngle();
		Vec3 flat = new Vec3(look.x, 0, look.z);
		Vec3 facing = flat.lengthSqr() < 1.0e-6 ? new Vec3(0, 0, -1) : flat.normalize();
		Vec3 side = new Vec3(-facing.z, 0, facing.x);

		return base.add(side.scale(right)).add(0, up, 0).add(facing.scale(forward));
	}

	/** The direction an effect as a whole is aimed, per {@link #AIM_NONE}/{@link #AIM_HORIZONTAL}/{@link #AIM_FULL}. */
	private static Vec3 aimVector(Entity entity, String aimMode) {
		Vec3 look = entity.getLookAngle();
		Vec3 flat = new Vec3(look.x, 0, look.z);
		Vec3 facing = flat.lengthSqr() < 1.0e-6 ? new Vec3(0, 0, -1) : flat.normalize();

		return switch (aimMode == null ? AIM_FULL : aimMode) {
			case AIM_NONE -> Vec3.ZERO;
			case AIM_HORIZONTAL -> facing;
			default -> look;
		};
	}
}
