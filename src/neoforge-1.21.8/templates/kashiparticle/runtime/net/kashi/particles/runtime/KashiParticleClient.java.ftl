package net.kashi.particles.runtime;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterParticleProvidersEvent;

import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.multiplayer.ClientLevel;

/**
 * Client-only registration: the particle render provider, plus loading and compiling the effects
 * this mod ships. Rendering is client-side, so the compiled effects live only here.
 *
 * <p>The provider is registered with {@code registerSpecial} rather than the sprite-based
 * overloads, because a KASHI effect binds its own texture and does not draw from the particle
 * atlas.
 *
 * <p>This is the NeoForge 1.21.8 variant of this file (see {@code runtime-1.21.8/} and
 * {@code tools/make-runtime-templates.ps1}) — identical to the 1.21.1 one except for the
 * {@code @EventBusSubscriber} annotation: see {@link KashiParticlesRuntime}'s 1.21.8 variant for
 * why {@code bus = EventBusSubscriber.Bus.MOD} is gone here too -
 * {@link RegisterParticleProvidersEvent} still implements {@code IModBusEvent}, so this still
 * routes to the mod bus without saying so explicitly.
 */
@EventBusSubscriber(modid = KashiParticlesRuntime.MODID, value = Dist.CLIENT)
public final class KashiParticleClient {

	private KashiParticleClient() {
	}

	@SubscribeEvent
	static void onRegisterProviders(RegisterParticleProvidersEvent event) {
		// KashiParticleEffects is generated from the workspace's KASHI Particle elements - one
		// registration per imported effect. It is regenerated whenever elements change.
		KashiParticleEffects.registerAll();

		event.registerSpecial(KashiParticlesRuntime.type(), new Provider());
	}

	/** Turns a spawn into the invisible emitter particle that drives the effect. */
	private static final class Provider implements ParticleProvider<KashiParticleOptions> {

		@Override
		public Particle createParticle(KashiParticleOptions options, ClientLevel level,
				double x, double y, double z, double dirX, double dirY, double dirZ) {
			KashiCompiledEffect effect = KashiParticleRegistry.get(options.effectId());

			if (effect == null)
				return null; // unknown effect id: nothing to render, but no crash

			return new KashiEmitterParticle(level, x, y, z, effect,
					options.dirX(), options.dirY(), options.dirZ(),
					options.entityId() == KashiParticleOptions.NO_ENTITY
							? null : level.getEntity(options.entityId()),
					options.scaleOffset(), options.durationOffset(), options.attachPoint(),
					options.effectId(), options.entityId());
		}
	}

	/** "Stop K4SH1 Particle" reaching the client - see {@code KashiParticlesRuntime#onRegisterPayloads}. */
	public static void stopMatchingParticles(net.minecraft.resources.ResourceLocation effectId, int entityId) {
		KashiActiveParticles.stopMatching(effectId, entityId);
	}
}
