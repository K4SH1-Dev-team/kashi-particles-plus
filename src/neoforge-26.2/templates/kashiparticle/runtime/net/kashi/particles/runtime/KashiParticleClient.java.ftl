package net.kashi.particles.runtime;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterParticleGroupsEvent;
import net.neoforged.neoforge.client.event.RegisterParticleProvidersEvent;

import net.minecraft.client.particle.Particle;
import net.minecraft.client.particle.ParticleProvider;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.util.RandomSource;

/**
 * Client-only registration: the particle render provider, plus loading and compiling the effects
 * this mod ships. Rendering is client-side, so the compiled effects live only here.
 *
 * <p>The provider is registered with {@code registerSpecial} rather than the sprite-based
 * overloads, because a KASHI effect binds its own texture and does not draw from the particle
 * atlas.
 *
 * <p>This is the NeoForge 26.1.2/26.2 variant of this file - two real differences from 1.21.1/
 * 1.21.8: no {@code bus=} attribute (see {@link KashiParticlesRuntime}), and a new {@code
 * onRegisterGroups} handler. Every earlier generator let {@code getGroup()} (né {@code
 * getRenderType()}) return a fresh, unique value per (texture, blend) and the engine created a
 * matching render batch for each automatically; 26.1.2/26.2 only creates one {@code ParticleGroup}
 * per DISTINCT {@code ParticleRenderType} for the whole game session, from a factory registered
 * once here - so {@link KashiRenderType#GROUP} (the one type every KASHI particle reports) needs
 * exactly one factory registration, not one per effect. See {@link KashiRenderType} and {@link
 * KashiParticleGroup} for where the per-(texture, blend) batching moved to instead.
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

	@SubscribeEvent
	static void onRegisterGroups(RegisterParticleGroupsEvent event) {
		event.register(KashiRenderType.GROUP, KashiParticleGroup::new);
	}

	/** Turns a spawn into the invisible emitter particle that drives the effect. */
	private static final class Provider implements ParticleProvider<KashiParticleOptions> {

		@Override
		public Particle createParticle(KashiParticleOptions options, ClientLevel level,
				double x, double y, double z, double dirX, double dirY, double dirZ, RandomSource random) {
			KashiCompiledEffect effect = KashiParticleRegistry.get(options.effectId());

			if (effect == null)
				return null; // unknown effect id: nothing to render, but no crash

			return new KashiEmitterParticle(level, x, y, z, effect,
					options.dirX(), options.dirY(), options.dirZ(),
					options.entityId() == KashiParticleOptions.NO_ENTITY
							? null : level.getEntity(options.entityId()),
					options.scaleOffset(), options.durationOffset());
		}
	}
}
