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
 * firing side is not the one the client renders â€” the client resolves the id against its own level.
 * It is only consulted by effects that declare {@code minecraft:emitter_local_space}.
 */
public record KashiParticleOptions(ResourceLocation effectId, float dirX, float dirY, float dirZ,
		int entityId) implements ParticleOptions {

	/** {@link #entityId} when the spawn is not tied to any entity. */
	public static final int NO_ENTITY = -1;

	public KashiParticleOptions(ResourceLocation effectId, float dirX, float dirY, float dirZ) {
		this(effectId, dirX, dirY, dirZ, NO_ENTITY);
	}

	public static final MapCodec<KashiParticleOptions> CODEC = RecordCodecBuilder.mapCodec(instance ->
			instance.group(
					ResourceLocation.CODEC.fieldOf("effect").forGetter(KashiParticleOptions::effectId),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dx").forGetter(KashiParticleOptions::dirX),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dy").forGetter(KashiParticleOptions::dirY),
					com.mojang.serialization.Codec.FLOAT.fieldOf("dz").forGetter(KashiParticleOptions::dirZ),
					com.mojang.serialization.Codec.INT.optionalFieldOf("entity", NO_ENTITY)
							.forGetter(KashiParticleOptions::entityId))
			.apply(instance, KashiParticleOptions::new));

	public static final StreamCodec<RegistryFriendlyByteBuf, KashiParticleOptions> STREAM_CODEC =
			StreamCodec.composite(
					ResourceLocation.STREAM_CODEC, KashiParticleOptions::effectId,
					ByteBufCodecs.FLOAT, KashiParticleOptions::dirX,
					ByteBufCodecs.FLOAT, KashiParticleOptions::dirY,
					ByteBufCodecs.FLOAT, KashiParticleOptions::dirZ,
					ByteBufCodecs.VAR_INT, KashiParticleOptions::entityId,
					KashiParticleOptions::new);

	@Override
	public ParticleType<?> getType() {
		return KashiParticlesRuntime.type();
	}
}
