package net.kashi.particles.runtime;

import com.mojang.blaze3d.pipeline.BlendFunction;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.platform.DestFactor;
import com.mojang.blaze3d.platform.SourceFactor;

import net.kashi.particles.core.KashiParticleDefinition.BlendMode;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.renderer.RenderPipelines;
import net.minecraft.client.renderer.RenderStateShard;
import net.minecraft.client.renderer.RenderType;
import net.minecraft.resources.ResourceLocation;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Builds the {@link ParticleRenderType} for one (texture, blend mode) combination.
 *
 * <p>This is the NeoForge 1.21.8 variant of this file (see {@code runtime-1.21.8/} and
 * {@code tools/make-runtime-templates.ps1}). The 1.21.1 build implements {@code ParticleRenderType}
 * as an interface and drives blend state imperatively through {@code RenderSystem}/
 * {@code GlStateManager} inside its own {@code begin(Tesselator, TextureManager)}. As of 1.21.8,
 * {@code ParticleRenderType} is a {@code final record} — it can no longer be implemented — and
 * Minecraft's own particle render types are built declaratively from a {@link RenderPipeline} and
 * a {@link RenderType} instead (confirmed reading {@code RenderType.java}/{@code
 * RenderPipelines.java} from the real 1.21.8 sources). This file follows that same pattern rather
 * than fighting it.
 *
 * <p>{@link #of} keeps the exact same static-factory shape the 1.21.1 build exposes
 * ({@code KashiRenderType.of(texture, blend) -> ParticleRenderType}), so {@code KashiParticle} and
 * {@code KashiEmitterParticle} - both shared, unmodified source between the two generators - need
 * no changes at all: they only ever call this method and return what it hands back.
 */
public final class KashiRenderType {

	private KashiRenderType() {
	}

	/**
	 * The one blend mode with no vanilla equivalent to reuse. {@link BlendFunction#ADDITIVE} is
	 * {@code (ONE, ONE)}, not alpha-weighted - it would draw even a near-transparent particle at
	 * full brightness. Bedrock's {@code particles_add} material (and the 1.21.1 build's own
	 * comment: "light accumulates, so overlaps glow") needs {@code (SRC_ALPHA, ONE)} instead, and
	 * additive particles must not write depth or they occlude the ones behind them and the glow
	 * stops accumulating - both set up here exactly once and shared by every KASHI effect that
	 * uses {@code ADD}, the same way {@code RenderPipelines.OPAQUE_PARTICLE} is built once and
	 * reused per-texture.
	 */
	private static final RenderPipeline ADDITIVE_PIPELINE =
			RenderPipeline.builder(RenderPipelines.PARTICLE_SNIPPET)
					.withLocation("kashi/pipeline/additive_particle")
					.withBlend(new BlendFunction(SourceFactor.SRC_ALPHA, DestFactor.ONE))
					.withDepthWrite(false)
					.build();

	private static final Map<String, ParticleRenderType> CACHE = new ConcurrentHashMap<>();

	public static ParticleRenderType of(ResourceLocation texture, BlendMode blend) {
		return CACHE.computeIfAbsent(texture + "|" + blend, key -> build(texture, blend));
	}

	private static ParticleRenderType build(ResourceLocation texture, BlendMode blend) {
		RenderType renderType = switch (blend) {
			// particles_alpha and particles_opaque are alpha *tested*, not blended: with no blend
			// pipeline, the vanilla particle shader's own "discard below 0.1 alpha" is the whole
			// transparency story, which is what gives them their hard edges - reusing vanilla's
			// own opaque particle pipeline verbatim, same as it does for its own particles.
			case CUTOUT, OPAQUE -> RenderType.opaqueParticle(texture);
			// Standard alpha blend, depth write on - exactly RenderPipelines.TRANSLUCENT_PARTICLE
			// (confirmed it does not disable depth write), so reusing it verbatim is correct here
			// too.
			case ALPHA -> RenderType.translucentParticle(texture);
			case ADD -> additive(texture);
		};

		// The name only has to be unique per distinct RenderType instance for batching/sorting
		// purposes; it never reaches the player.
		return new ParticleRenderType("kashi_" + blend, renderType);
	}

	private static RenderType additive(ResourceLocation texture) {
		return RenderType.create("kashi_additive_particle", 1536, ADDITIVE_PIPELINE,
				RenderType.CompositeState.builder()
						.setTextureState(new RenderStateShard.TextureStateShard(texture, false))
						.setLightmapState(RenderStateShard.LIGHTMAP)
						.createCompositeState(false));
	}
}
