package net.kashi.particles.runtime;

import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.ByteBufCodecs;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.Identifier;

/**
 * Sent server-to-client to end every currently-running KASHI effect matching an
 * {@code (effectId, entityId)} pair — see {@code KashiParticleAPI#stopKashiParticle} for how it is
 * sent and {@code KashiActiveParticles} for how it is matched against live instances client-side.
 *
 * <p>{@link #entityId} uses the same {@code KashiParticleOptions.NO_ENTITY} sentinel a spawn
 * packet does: a Stop naming no entity matches every no-owner instance of the effect (world/block
 * spawns), exactly mirroring how those spawns already travel under that sentinel today. Nothing
 * here invents a new identity scheme — it reuses the one {@code KashiParticleOptions} already has.
 */
public record KashiStopParticlesPayload(Identifier effectId, int entityId) implements CustomPacketPayload {

	public static final Type<KashiStopParticlesPayload> TYPE = new Type<>(
			Identifier.fromNamespaceAndPath(KashiParticlesRuntime.MODID, "stop_particles"));

	public static final StreamCodec<RegistryFriendlyByteBuf, KashiStopParticlesPayload> STREAM_CODEC =
			StreamCodec.composite(
					Identifier.STREAM_CODEC, KashiStopParticlesPayload::effectId,
					ByteBufCodecs.VAR_INT, KashiStopParticlesPayload::entityId,
					KashiStopParticlesPayload::new);

	@Override
	public Type<? extends CustomPacketPayload> type() {
		return TYPE;
	}
}
