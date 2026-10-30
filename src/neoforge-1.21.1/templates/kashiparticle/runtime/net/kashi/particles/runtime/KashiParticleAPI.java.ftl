package net.kashi.particles.runtime;

import net.neoforged.neoforge.network.PacketDistributor;

import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
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
	 * <p>On the server, {@link Level#addParticle} is a no-op — its body is empty on {@code Level}
	 * and {@code ServerLevel} does not override it, so calling it server-side never reaches a
	 * client. {@link ServerLevel#sendParticles} is the real broadcast, and passing
	 * {@code longDistance = true} widens the broadcast radius from 32 to 512 blocks, so a distant
	 * effect that is genuinely in view still arrives. On the client, {@code addParticle} spawns
	 * locally as before.
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ, int entityId,
			float scaleOffset, float durationOffset) {
		spawnKashiParticle(level, effectId, x, y, z, dirX, dirY, dirZ, entityId,
				scaleOffset, durationOffset, "");
	}

	/**
	 * As the overload below, following the entity's whole look ({@link #AIM_FULL}) - what an
	 * attached spawn did before the aim mode was carried through to the emitter.
	 */
	public static void spawnKashiParticle(Level level, ResourceLocation effectId,
			double x, double y, double z, double dirX, double dirY, double dirZ, int entityId,
			float scaleOffset, float durationOffset, String attachPoint) {
		spawnKashiParticle(level, effectId, x, y, z, dirX, dirY, dirZ, entityId, scaleOffset,
				durationOffset, attachPoint, AIM_FULL);
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
			float scaleOffset, float durationOffset, String attachPoint, String aimMode) {
		ParticleOptions options = new KashiParticleOptions(effectId,
				(float) dirX, (float) dirY, (float) dirZ, entityId,
				new KashiParticleOptions.Extras(scaleOffset, durationOffset, attachPoint, aimMode));

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
	 * <p>Position AND rotation both follow - unlike a plain {@code minecraft:emitter_local_space}
	 * effect (which only turns with yaw, deliberately never pitch - see {@code
	 * KashiEmitterParticle#yawFrame}), an attached effect follows the FULL look direction, pitch
	 * included: turning to look up or down turns the effect (and any offset it has) the same way,
	 * which is what makes a HEAD/EYE anchor with a forward offset feel attached rather than merely
	 * nearby. See {@code KashiEmitterParticle#fullLookFrame}.
	 *
	 * <p>Like every KASHI spawn, this is still bounded by the emitter's own fire-and-forget lifetime
	 * cap - an attached looping effect still ends on its own after at most 30 seconds, even though
	 * it kept following the entity right up until then. There is no way to attach one that runs
	 * until the entity itself does something to end it; that needs a way to name and later stop a
	 * running instance, which this does not provide.
	 *
	 * @param attachPoint {@code "ROOT"} (root/body), {@code "HEAD"}, {@code "EYE"}, or one of
	 *                    {@code "HAND_RIGHT"}/{@code "HAND_LEFT"}/{@code "FOOT_RIGHT"}/
	 *                    {@code "FOOT_LEFT"} - see {@link #resolveAttachPoint} for what each names
	 *                    and {@link #resolveLimbSwingRadians} for how the limb ones also turn the
	 *                    effect as the limb swings
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
				entity.getId(), scaleOffset, durationOffset, attachPoint, aimMode);
	}

	/**
	 * Ends every currently-running instance of {@code effectId} owned by {@code entity} - a world/
	 * entity/block spawn, or an attach, fired directly through this API (not one fired as another
	 * effect's own chained event; see {@code KashiActiveParticles} for why). {@code entity == null}
	 * targets every no-owner instance instead (world/block spawns), the same
	 * {@code KashiParticleOptions.NO_ENTITY} sentinel those already spawn under.
	 *
	 * <p>Stops the emitter the same way a natural expiration would: no more new particles, but
	 * everything it already spawned keeps fading out on its own. See {@link #despawnKashiParticle}
	 * for a full, instant cutoff instead.
	 */
	public static void stopKashiParticle(Level level, ResourceLocation effectId, Entity entity) {
		sendStopPacket(level, effectId, entity, false);
	}

	/**
	 * As {@link #stopKashiParticle}, but also removes every particle the matching instance(s)
	 * already spawned instead of letting them fade out - a full, instant cutoff rather than just
	 * ending the (invisible) emitter that was still spawning more.
	 */
	public static void despawnKashiParticle(Level level, ResourceLocation effectId, Entity entity) {
		sendStopPacket(level, effectId, entity, true);
	}

	/**
	 * Shared by {@link #stopKashiParticle} and {@link #despawnKashiParticle} - sending and matching
	 * are identical between the two; only which {@code KashiActiveParticles} method the client ends
	 * up calling differs, carried as {@code despawn} in the packet itself
	 * ({@code KashiStopParticlesPayload}).
	 *
	 * <p>Sends a new packet rather than reusing {@link ServerLevel#sendParticles} the way every
	 * spawn does, because there is no vanilla "un-spawn a particle" concept to piggyback on; a
	 * dedicated client-side registry ({@code KashiActiveParticles}) is what actually matches the id
	 * against live instances.
	 *
	 * <p>Mirrors {@link #spawnKashiParticle}'s own client/server split: on the server, broadcasts to
	 * every player in the dimension, same as every spawn. When {@code level} is not a
	 * {@link ServerLevel} - a procedure that runs client-side, as some trigger types do - this runs
	 * on an actual client already, so it acts on the matching instances directly instead of sending
	 * a packet nobody would answer. This branch can only ever run on a real client: a dedicated
	 * server has no {@code Level} that is not a {@link ServerLevel}.
	 */
	private static void sendStopPacket(Level level, ResourceLocation effectId, Entity entity, boolean despawn) {
		int entityId = entity == null ? KashiParticleOptions.NO_ENTITY : entity.getId();

		if (level instanceof ServerLevel serverLevel)
			PacketDistributor.sendToPlayersInDimension(serverLevel,
					new KashiStopParticlesPayload(effectId, entityId, despawn));
		else
			KashiParticleClient.stopMatchingParticles(effectId, entityId, despawn);
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
	 *
	 * <p>{@code "HAND_RIGHT"}/{@code "HAND_LEFT"}/{@code "FOOT_RIGHT"}/{@code "FOOT_LEFT"} are the
	 * same kind of visually-tuned approximation, driven by {@link LivingEntity#getAttackAnim} and
	 * {@link LivingEntity#walkAnimation} rather than a real arm/leg bone - see {@link #resolveHand}/
	 * {@link #resolveFoot}. An {@link Entity} that is not a {@link LivingEntity} (a dropped item,
	 * say) falls back to the same point as {@code "ROOT"} for these four - no crash, just a less
	 * interesting result for something with no limbs to swing.
	 */
	public static Vec3 resolveAttachPoint(Entity entity, String attachPoint) {
		return switch (attachPoint) {
			case "ROOT" -> entity.position();
			case "HEAD" -> entity.position().add(0, entity.getBbHeight() * 0.9, 0);
			case "HAND_RIGHT" -> resolveHand(entity, true);
			case "HAND_LEFT" -> resolveHand(entity, false);
			case "FOOT_RIGHT" -> resolveFoot(entity, true);
			case "FOOT_LEFT" -> resolveFoot(entity, false);
			default -> entity.getEyePosition(); // "" (legacy) and "EYE" both land here
		};
	}

	/**
	 * How far {@code KashiEmitterParticle#followFrame} should tilt the rotation frame beyond the
	 * entity's own look direction, so an effect attached to a hand/foot turns as the limb swings -
	 * {@code 0} (no extra tilt) for every other attach point, or when {@code entity} is not a
	 * {@link LivingEntity}. Lives here rather than in {@code KashiEmitterParticle} (which is the
	 * only caller - this is a client-only concern, the server never needs to know which way an
	 * effect is turned) so it can share {@link LimbAnimState} with {@link #resolveHand}/
	 * {@link #resolveFoot} instead of reading {@code walkAnimation}/{@code getAttackAnim} twice.
	 */
	public static float resolveLimbSwingRadians(Entity entity, String attachPoint) {
		if (!(entity instanceof LivingEntity living))
			return 0f;
		return switch (attachPoint) {
			case "HAND_RIGHT", "HAND_LEFT" -> handSwingRadians(LimbAnimState.of(living));
			case "FOOT_RIGHT", "FOOT_LEFT" ->
					footSwingRadians(LimbAnimState.of(living), attachPoint.equals("FOOT_RIGHT"));
			default -> 0f;
		};
	}

	// Calibration constants for the hand/foot approximation - initial guesses, tuned against how
	// they actually look in-game (Player and a vanilla biped) rather than treated as exact.
	private static final double SHOULDER_HEIGHT = 1.3;
	private static final double ARM_WIDTH = 0.3;
	private static final double ARM_LENGTH = 0.6;
	private static final double ARM_DROP = 0.6; // how far a resting hand hangs below the shoulder
	private static final double LEG_WIDTH = 0.15;
	private static final double STRIDE_LENGTH = 0.3;
	private static final float MAX_HAND_SWING = (float) Math.toRadians(60);
	private static final float MAX_FOOT_SWING = (float) Math.toRadians(35);

	/**
	 * The three animation readings {@link #resolveHand}/{@link #resolveFoot}/
	 * {@link #resolveLimbSwingRadians} all need, read once per call instead of each reaching into
	 * {@code walkAnimation}/{@code getAttackAnim} separately.
	 */
	private record LimbAnimState(float attack, float swingAmount, float swingPhase) {
		static LimbAnimState of(LivingEntity living) {
			return new LimbAnimState(living.getAttackAnim(1.0f), living.walkAnimation.speed(1.0f),
					living.walkAnimation.position(1.0f));
		}
	}

	/**
	 * Approximated from swing/attack animation state, calibrated visually - not a literal read of
	 * the entity's actual arm pose. Falls back to {@code "ROOT"}'s point when {@code entity} is not
	 * a {@link LivingEntity} (see {@link #resolveAttachPoint}).
	 */
	private static Vec3 resolveHand(Entity entity, boolean rightSide) {
		if (!(entity instanceof LivingEntity living))
			return entity.position();
		LimbAnimState anim = LimbAnimState.of(living);
		double side = (rightSide ? 1 : -1) * ARM_WIDTH; // right positive = the entity's actual right
		double forward = anim.attack() * ARM_LENGTH
				+ Math.sin(anim.swingPhase() * 0.6662) * anim.swingAmount() * 0.1; // walking sway
		double up = SHOULDER_HEIGHT - ARM_DROP * (1 - anim.attack()); // hangs at rest, rises into the punch
		return entityFrameOffset(living, living.position(), side, up, forward);
	}

	/** Same approximation as {@link #resolveHand}, for a foot instead - see its doc comment. */
	private static Vec3 resolveFoot(Entity entity, boolean rightSide) {
		if (!(entity instanceof LivingEntity living))
			return entity.position();
		LimbAnimState anim = LimbAnimState.of(living);
		double phaseOffset = rightSide ? 0 : Math.PI; // legs alternate, same as vanilla walk animation
		double side = (rightSide ? 1 : -1) * LEG_WIDTH;
		double forward = Math.sin(anim.swingPhase() * 0.6662 + phaseOffset) * anim.swingAmount() * STRIDE_LENGTH;
		return entityFrameOffset(living, living.position(), side, 0, forward); // up=0: foot on the ground
	}

	/** The extra rotation {@link #resolveLimbSwingRadians} applies for a hand - see its doc comment. */
	private static float handSwingRadians(LimbAnimState anim) {
		return anim.attack() * MAX_HAND_SWING
				+ (float) Math.sin(anim.swingPhase() * 0.6662) * anim.swingAmount() * 0.2f;
	}

	/** The extra rotation {@link #resolveLimbSwingRadians} applies for a foot - see its doc comment. */
	private static float footSwingRadians(LimbAnimState anim, boolean rightSide) {
		double phaseOffset = rightSide ? 0 : Math.PI;
		return (float) (Math.sin(anim.swingPhase() * 0.6662 + phaseOffset) * anim.swingAmount()) * MAX_FOOT_SWING;
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
