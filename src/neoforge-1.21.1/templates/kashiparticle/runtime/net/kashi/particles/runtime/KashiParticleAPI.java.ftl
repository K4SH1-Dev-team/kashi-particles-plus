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
	 * <p>On the server, {@link Level#addParticle} is a no-op â€” its body is empty on {@code Level}
	 * and {@code ServerLevel} does not override it, so calling it server-side never reaches a
	 * client. {@link ServerLevel#sendParticles} is the real broadcast, and passing
	 * {@code longDistance = true} widens the broadcast radius from 32 to 512 blocks, so a distant
	 * effect that is genuinely in view still arrives. On the client, {@code addParticle} spawns
	 * locally as before.
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ, int entityId,
			float scaleOffset, float durationOffset) {
		ParticleOptions options = new KashiParticleOptions(effectId,
				(float) dirX, (float) dirY, (float) dirZ, entityId,
				new KashiParticleOptions.Extras(scaleOffset, durationOffset));

		if (level instanceof ServerLevel serverLevel) {
			for (ServerPlayer player : serverLevel.players())
				serverLevel.sendParticles(player, options, true, x, y, z, 0, 0, 0, 0, 0);
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

		Vec3 look = entity.getLookAngle();
		Vec3 flat = new Vec3(look.x, 0, look.z);
		Vec3 facing = flat.lengthSqr() < 1.0e-6 ? new Vec3(0, 0, -1) : flat.normalize();
		Vec3 side = new Vec3(-facing.z, 0, facing.x);

		Vec3 origin = entity.position()
				.add(side.scale(right))
				.add(0, up, 0)
				.add(facing.scale(forward));

		Vec3 aim = switch (aimMode == null ? AIM_FULL : aimMode) {
			case AIM_NONE -> Vec3.ZERO;
			case AIM_HORIZONTAL -> facing;
			default -> look;
		};

		spawnKashiParticle(level, effectId, origin.x, origin.y, origin.z, aim.x, aim.y, aim.z,
				entity.getId(), scaleOffset, durationOffset);
	}
}
