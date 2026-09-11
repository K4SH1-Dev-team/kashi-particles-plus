package net.kashi.particles.runtime;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterParticleGroupsEvent;
import net.neoforged.neoforge.client.event.RegisterParticleProvidersEvent;
import net.neoforged.neoforge.client.event.RegisterRenderPipelinesEvent;

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
 * <p>This is the NeoForge 26.1.2/26.2 variant of this file - real differences from 1.21.1/1.21.8:
 * no {@code bus=} attribute (see {@link KashiParticlesRuntime}), a new {@code onRegisterGroups}
 * handler, and a new {@code onRegisterPipelines} handler. Every earlier generator let {@code
 * getGroup()} (né {@code getRenderType()}) return a fresh, unique value per (texture, blend) and
 * the engine created a matching render batch for each automatically; 26.1.2/26.2 only creates one
 * {@code ParticleGroup} per DISTINCT {@code ParticleRenderType} for the whole game session, from a
 * factory registered once here - so {@link KashiRenderType#GROUP} (the one type every KASHI
 * particle reports) needs exactly one factory registration, not one per effect. See {@link
 * KashiRenderType} and {@link KashiParticleGroup} for where the per-(texture, blend) batching moved
 * to instead.
 *
 * <p>{@code onRegisterPipelines} exists because every vanilla particle pipeline on 26.1.2/26.2 goes
 * through {@code RenderPipelines.register(...)} (visible in the real 26.1.2/26.2 source: {@code
 * OPAQUE_PARTICLE}/{@code TRANSLUCENT_PARTICLE} are both wrapped in a private {@code register()}
 * that puts them in {@code PIPELINES_BY_LOCATION}) before the engine ever binds them - and no
 * vanilla particle uses an additive blend through this API to prove that step is skippable (every
 * built-in {@code SingleQuadParticle.Layer} constant is {@code OPAQUE} or {@code TRANSLUCENT}, never
 * additive). {@link KashiRenderType#ADDITIVE_PIPELINE} is the one pipeline KASHI builds itself
 * rather than reusing a vanilla one, and skipping this step is the one confirmed structural gap
 * between it and every vanilla pipeline - registering it here, through the same {@code
 * RegisterRenderPipelinesEvent} vanilla's own {@code registerCustomPipelines()} uses, closes that
 * gap instead of relying on undocumented lazy-registration behaviour.
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

	@SubscribeEvent
	static void onRegisterPipelines(RegisterRenderPipelinesEvent event) {
		event.registerPipeline(KashiRenderType.ADDITIVE_PIPELINE);
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
					options.scaleOffset(), options.durationOffset(), options.attachPoint(),
					options.effectId(), options.entityId());
		}
	}

	/** "Stop K4SH1 Particle" reaching the client - see {@code KashiParticlesRuntime#onRegisterPayloads}. */
	public static void stopMatchingParticles(net.minecraft.resources.Identifier effectId, int entityId) {
		KashiActiveParticles.stopMatching(effectId, entityId);
	}
}
