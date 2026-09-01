package net.kashi.particles.runtime;

import com.mojang.serialization.MapCodec;
import com.mojang.serialization.codecs.RecordCodecBuilder;

import net.minecraft.core.particles.ParticleOptions;
import net.minecraft.core.particles.ParticleType;
import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.resources.ResourceLocation;

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
 * <p>{@link #extras} carries the additive scale/duration offsets (see {@link Extras}). They are
 * grouped into their own record rather than sitting alongside the other fields because
 * {@link StreamCodec#composite} tops out at six type parameters and this record was already at
 * five - nesting keeps both codecs under that limit instead of requiring a hand-written one.
 */
public record KashiParticleOptions(ResourceLocation effectId, float dirX, float dirY, float dirZ,
		int entityId, Extras extras) implements ParticleOptions {

	/** {@link #entityId} when the spawn is not tied to any entity. */
	public static final int NO_ENTITY = -1;

	public KashiParticleOptions(ResourceLocation effectId, float dirX, float dirY, float dirZ) {
		this(effectId, dirX, dirY, dirZ, NO_ENTITY, Extras.NONE);
	}

	public KashiParticleOptions(ResourceLocation effectId, float dirX, float dirY, float dirZ,
			int entityId) {
		this(effectId, dirX, dirY, dirZ, entityId, Extras.NONE);
	}

	/** {@link #extras}'s accessor is the record's own; these read straight through it. */
	public float scaleOffset() {
		return this.extras.scaleOffset();
	}

	public float durationOffset() {
		return this.extras.durationOffset();
	}

	/**
	 * Additive scale/duration offsets a spawn can apply on top of what the effect authored in
	 * Snowstorm. Both default to {@code 0}, which is a no-op â€” per the plugin's governing rule,
	 * an unfilled offset always leaves Snowstorm as the source of truth.
	 *
	 * @param scaleOffset    added to the authored half-width/half-height every frame, floored at 0
	 * @param durationOffset added to the emitter's {@code active_time} (how long it keeps spawning
	 *                       new particles) - not to any individual particle's {@code max_lifetime}
	 */
	public record Extras(float scaleOffset, float durationOffset) {

		public static final Extras NONE = new Extras(0, 0);

		static final StreamCodec<net.minecraft.network.FriendlyByteBuf, Extras> STREAM_CODEC =
				StreamCodec.composite(
						ByteBufCodecs.FLOAT, Extras::scaleOffset,
						ByteBufCodecs.FLOAT, Extras::durationOffset,
						Extras::new);
	}

	public static final MapCodec<KashiParticleOptions> CODEC = RecordCodecBuilder.mapCodec(instance ->
			instance.group(
					ResourceLocation.CODEC.fieldOf("effect").forGetter(KashiParticleOptions::effectId),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dx").forGetter(KashiParticleOptions::dirX),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dy").forGetter(KashiParticleOptions::dirY),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dz").forGetter(KashiParticleOptions::dirZ),
					com.mojang.serialization.Codec.INT.optionalFieldOf("entity", NO_ENTITY)
							.forGetter(KashiParticleOptions::entityId),
					com.mojang.serialization.Codec.FLOAT.optionalFieldOf("scale", 0f)
							.forGetter(KashiParticleOptions::scaleOffset),
					com.mojang.serialization.Codec.FLOAT.optionalFieldOf("duration", 0f)
							.forGetter(KashiParticleOptions::durationOffset))
			.apply(instance, (effectId, dx, dy, dz, entity, scale, duration) ->
					new KashiParticleOptions(effectId, dx, dy, dz, entity, new Extras(scale, duration))));

	public static final StreamCodec<RegistryFriendlyByteBuf, KashiParticleOptions> STREAM_CODEC =
			StreamCodec.composite(
					ResourceLocation.STREAM_CODEC, KashiParticleOptions::effectId,
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
