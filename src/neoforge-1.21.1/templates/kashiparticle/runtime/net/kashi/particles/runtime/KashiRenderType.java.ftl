package net.kashi.particles.runtime;

import com.mojang.blaze3d.platform.GlStateManager;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.Tesselator;
import com.mojang.blaze3d.vertex.VertexFormat;

import net.kashi.particles.core.KashiParticleDefinition.BlendMode;
import net.minecraft.client.renderer.GameRenderer;
import net.minecraft.client.renderer.texture.TextureManager;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.resources.ResourceLocation;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * A particle render pass bound to one texture and one blend mode.
 *
 * <p>Vanilla's built-in render types all draw from the shared particle atlas; a KASHI effect owns
 * its own PNG, so we bind that texture ourselves in {@link #begin} and pick the blend function
 * from the effect's Bedrock material.
 *
 * <p>The particle engine batches particles by render-type identity: it calls {@link #begin} once,
 * draws every particle that returns the same instance, then ends. So instances are interned by
 * (texture, blend) â€” two particles sharing a texture and blend share one batch, which is both
 * correct and fast. Additive blends must not be batched with alpha ones.
 */
public final class KashiRenderType implements ParticleRenderType {

	private static final Map<String, KashiRenderType> CACHE = new ConcurrentHashMap<>();

	private final ResourceLocation texture;
	private final BlendMode blend;

	private KashiRenderType(ResourceLocation texture, BlendMode blend) {
		this.texture = texture;
		this.blend = blend;
	}

	public static KashiRenderType of(ResourceLocation texture, BlendMode blend) {
		return CACHE.computeIfAbsent(texture + "|" + blend, key -> new KashiRenderType(texture, blend));
	}

	@Override
	public BufferBuilder begin(Tesselator tesselator, TextureManager textureManager) {
		RenderSystem.setShader(GameRenderer::getParticleShader);
		RenderSystem.setShaderTexture(0, this.texture);

		switch (this.blend) {
			// particles_add: light accumulates, so overlaps glow. SRC_ALPHA, ONE.
			case ADD -> {
				RenderSystem.enableBlend();
				RenderSystem.blendFunc(GlStateManager.SourceFactor.SRC_ALPHA,
						GlStateManager.DestFactor.ONE);
			}
			case ALPHA -> {
				RenderSystem.enableBlend();
				RenderSystem.defaultBlendFunc();
			}
			// particles_alpha and particles_opaque are alpha *tested*, not blended: with blending
			// off, the vanilla particle shader's own "discard below 0.1 alpha" is the whole
			// transparency story, which is what gives them their hard edges. Leaving blending on
			// here is what made an author's crisp sprite come out soft.
			case CUTOUT, OPAQUE -> RenderSystem.disableBlend();
		}

		// Additive particles should not write depth, or they occlude the ones behind them and the
		// glow stops accumulating. Everything else keeps the vanilla behaviour.
		RenderSystem.depthMask(this.blend != BlendMode.ADD);

		return tesselator.begin(VertexFormat.Mode.QUADS, DefaultVertexFormat.PARTICLE);
	}

	@Override
	public boolean isTranslucent() {
		// Drives whether the engine sorts these back-to-front. A cutout has nothing to sort: every
		// pixel is either fully there or gone, so sorting only costs time.
		return this.blend != BlendMode.CUTOUT && this.blend != BlendMode.OPAQUE;
	}

	@Override
	public String toString() {
		return "KASHI[" + this.texture + ", " + this.blend + "]";
	}
}
