package net.kashi.particles.runtime;

import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.registries.RegisterEvent;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;

/**
 * Common-side registration for the KASHI particle system.
 *
 * <p>All KASHI effects spawn under one {@link KashiParticleType}; it is registered here on the mod
 * event bus. Client-only concerns â€” the render provider and the compiled effect registry â€” live in
 * {@link KashiParticleClient}.
 */
@EventBusSubscriber(modid = KashiParticlesRuntime.MODID, bus = EventBusSubscriber.Bus.MOD)
public final class KashiParticlesRuntime {

	public static final String MODID = "${modid}";

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
}
