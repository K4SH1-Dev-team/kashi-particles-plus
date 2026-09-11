package net.kashi.particles.runtime;

import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.registries.RegisterEvent;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;

/**
 * Common-side registration for the KASHI particle system.
 *
 * <p>All KASHI effects spawn under one {@link KashiParticleType}; it is registered here on the mod
 * event bus. Client-only concerns — the render provider and the compiled effect registry — live in
 * {@link KashiParticleClient}.
 */
@EventBusSubscriber(modid = KashiParticlesRuntime.MODID, bus = EventBusSubscriber.Bus.MOD)
public final class KashiParticlesRuntime {

	public static final String MODID = "kashi_particle_test";

	/** The registered type id; the same string a spawn packet carries as its ParticleType. */
	public static final ResourceLocation TYPE_ID = ResourceLocation.fromNamespaceAndPath(MODID, "kashi_particle");

	// Assigned during registration, before any spawn can occur. Read by KashiParticleOptions.
	private static KashiParticleType type;

	private KashiParticlesRuntime() {
	}

	public static KashiParticleType type() {
		return type;
	}

	@SubscribeEvent
	static void onRegister(RegisterEvent event) {
		event.register(Registries.PARTICLE_TYPE, TYPE_ID, () -> {
			type = new KashiParticleType();
			return type;
		});
	}

	/**
	 * Registers the S2C "stop" packet. This runs on both physical sides (a {@code RegisterEvent}-
	 * style mod-bus event fires on a dedicated server too), but {@link KashiParticleClient} — which
	 * the handler defers to — is client-only. Wrapping the reference inside the
	 * {@code context.enqueueWork} lambda keeps it unresolved until a packet actually arrives, which
	 * only ever happens on a real client, so a dedicated server never loads that class.
	 */
	@SubscribeEvent
	static void onRegisterPayloads(RegisterPayloadHandlersEvent event) {
		event.registrar("1").playToClient(KashiStopParticlesPayload.TYPE, KashiStopParticlesPayload.STREAM_CODEC,
				(payload, context) -> context.enqueueWork(
						() -> KashiParticleClient.stopMatchingParticles(payload.effectId(), payload.entityId())));
	}
}
