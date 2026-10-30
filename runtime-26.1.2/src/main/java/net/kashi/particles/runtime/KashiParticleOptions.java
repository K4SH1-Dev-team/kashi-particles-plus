package net.kashi.particles.runtime;

import com.mojang.serialization.MapCodec;
import com.mojang.serialization.codecs.RecordCodecBuilder;

import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.core.particles.ParticleType;
import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.resources.Identifier;

/**
 * The payload carried when a KASHI particle is spawned: which effect to play and the world-space
 * direction the emitter should aim along.
 *
 * <p>Every KASHI effect shares one registered {@link ParticleType}; the effect identity travels
 * in the options, not the type. That keeps registration to a single type no matter how many
 * effects a mod imports, and lets a spawn name its effect by id.
 *
 * <p>The codecs exist because a procedure firing on the server sends the spawn to clients as a
 * packet; the stream codec is what crosses the wire.
 *
 * <p>{@link #entityId} travels rather than an entity reference, because the entity object on the
 * firing side is not the one the client renders — the client resolves the id against its own level.
 * It is only consulted by effects that declare {@code minecraft:emitter_local_space}.
 *
 * <p>{@link #extras} carries the additive scale/duration offsets and the attach point (see
 * {@link Extras}). They are grouped into their own record rather than sitting alongside the other
 * fields because {@link StreamCodec#composite} tops out at six type parameters and this record
 * was already at five - nesting keeps both codecs under that limit instead of requiring a
 * hand-written one.
 */
public record KashiParticleOptions(Identifier effectId, float dirX, float dirY, float dirZ,
		int entityId, Extras extras) implements ParticleOptions {

	/** {@link #entityId} when the spawn is not tied to any entity. */
	public static final int NO_ENTITY = -1;

	public KashiParticleOptions(Identifier effectId, float dirX, float dirY, float dirZ) {
		this(effectId, dirX, dirY, dirZ, NO_ENTITY, Extras.NONE);
	}

	public KashiParticleOptions(Identifier effectId, float dirX, float dirY, float dirZ,
			int entityId) {
		this(effectId, dirX, dirY, dirZ, entityId, Extras.NONE);
	}

	/** {@link #extras}'s accessors are the record's own; these read straight through it. */
	public float scaleOffset() {
		return this.extras.scaleOffset();
	}

	public float durationOffset() {
		return this.extras.durationOffset();
	}

	/** Which point on {@link #entityId} to track; empty for every spawn except an Attach one. */
	public String attachPoint() {
		return this.extras.attachPoint();
	}

	/**
	 * How an Attach spawn keeps following its entity: {@code FULL}, {@code HORIZONTAL} or
	 * {@code NONE} - see {@code KashiParticleAPI#AIM_FULL}. {@code FULL} for every other spawn, where
	 * it is never consulted.
	 */
	public String aimMode() {
		return this.extras.aimMode();
	}

	/**
	 * Additive scale/duration offsets a spawn can apply on top of what the effect authored in
	 * Snowstorm, plus the attach point for "Attach K4SH1 Particle to Entity". The offsets default
	 * to {@code 0}, which is a no-op — per the plugin's governing rule, an unfilled offset always
	 * leaves Snowstorm as the source of truth; {@code attachPoint} defaults to {@code ""}, which
	 * leaves {@link #entityId} consulted only by an effect that authors
	 * {@code minecraft:emitter_local_space} itself, exactly as before this field existed.
	 *
	 * @param scaleOffset    added to the authored half-width/half-height every frame, floored at 0
	 * @param durationOffset added to the emitter's {@code active_time} (how long it keeps spawning
	 *                       new particles) - not to any individual particle's {@code max_lifetime}
	 * @param attachPoint    {@code "ROOT"}, {@code "HEAD"} or {@code "EYE"} - see
	 *                       {@code KashiEmitterParticle#resolveAnchorPosition()}
	 * @param aimMode        {@code FULL}, {@code HORIZONTAL} or {@code NONE}: which part of the entity's
	 *                       look an Attach spawn keeps following (see {@code KashiEmitterParticle#followFrame})
	 */
	public record Extras(float scaleOffset, float durationOffset, String attachPoint, String aimMode) {

		public static final Extras NONE = new Extras(0, 0, "", "FULL");

		static final StreamCodec<net.minecraft.network.FriendlyByteBuf, Extras> STREAM_CODEC =
				StreamCodec.composite(
						ByteBufCodecs.FLOAT, Extras::scaleOffset,
						ByteBufCodecs.FLOAT, Extras::durationOffset,
						ByteBufCodecs.stringUtf8(32), Extras::attachPoint,
						ByteBufCodecs.stringUtf8(16), Extras::aimMode,
						Extras::new);
	}

	public static final MapCodec<KashiParticleOptions> CODEC = RecordCodecBuilder.mapCodec(instance ->
			instance.group(
					Identifier.CODEC.fieldOf("effect").forGetter(KashiParticleOptions::effectId),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dx").forGetter(KashiParticleOptions::dirX),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dy").forGetter(KashiParticleOptions::dirY),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dz").forGetter(KashiParticleOptions::dirZ),
					com.mojang.serialization.Codec.INT.optionalFieldOf("entity", NO_ENTITY)
							.forGetter(KashiParticleOptions::entityId),
					com.mojang.serialization.Codec.FLOAT.optionalFieldOf("scale", 0f)
							.forGetter(KashiParticleOptions::scaleOffset),
					com.mojang.serialization.Codec.FLOAT.optionalFieldOf("duration", 0f)
							.forGetter(KashiParticleOptions::durationOffset),
					com.mojang.serialization.Codec.STRING.optionalFieldOf("attach", "")
							.forGetter(KashiParticleOptions::attachPoint),
					com.mojang.serialization.Codec.STRING.optionalFieldOf("aim", "FULL")
							.forGetter(KashiParticleOptions::aimMode))
			.apply(instance, (effectId, dx, dy, dz, entity, scale, duration, attach, aim) ->
					new KashiParticleOptions(effectId, dx, dy, dz, entity, new Extras(scale, duration, attach, aim))));

	public static final StreamCodec<RegistryFriendlyByteBuf, KashiParticleOptions> STREAM_CODEC =
			StreamCodec.composite(
					Identifier.STREAM_CODEC, KashiParticleOptions::effectId,
					ByteBufCodecs.FLOAT, KashiParticleOptions::dirX,
					ByteBufCodecs.FLOAT, KashiParticleOptions::dirY,
					ByteBufCodecs.FLOAT, KashiParticleOptions::dirZ,
					ByteBufCodecs.VAR_INT, KashiParticleOptions::entityId,
					Extras.STREAM_CODEC, KashiParticleOptions::extras,
					KashiParticleOptions::new);

	@Override
	public ParticleType<?> getType() {
		return KashiParticlesRuntime.type();
	}
}
