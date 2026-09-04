package net.kashi.particles.runtime;

import com.mojang.blaze3d.pipeline.BlendFunction;
import com.mojang.blaze3d.pipeline.ColorTargetState;
import com.mojang.blaze3d.pipeline.DepthStencilState;
import com.mojang.blaze3d.pipeline.RenderPipeline;
import com.mojang.blaze3d.platform.BlendFactor;
import com.mojang.blaze3d.platform.CompareOp;

import net.kashi.particles.core.KashiParticleDefinition.BlendMode;
import net.minecraft.client.Minecraft;
import net.minecraft.client.particle.ParticleRenderType;
import net.minecraft.client.particle.SingleQuadParticle;
import net.minecraft.client.renderer.RenderPipelines;
import net.minecraft.resources.Identifier;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The NeoForge 26.2 variant of this file - almost identical to the 26.1.2 one (see that file for
 * the shared background), except for two small real API differences confirmed against the real
 * 26.2 source rather than assumed from 26.1.2: {@code ParticleRenderType} takes a second {@code
 * String shorthand} argument now, and {@code SourceFactor}/{@code DestFactor} were merged into one
 * {@code BlendFactor} enum.
 *
 * <p>{@code ParticleRenderType} stopped being a per-(texture, blend) object some time after 1.21.8
 * - confirmed reading the real 26.1.2 source: it is now a plain named marker (4 fixed vanilla
 * constants plus whatever a mod registers of its own), and the engine only creates one {@code
 * ParticleGroup} per distinct {@code ParticleRenderType} for the entire game session (registered
 * once via NeoForge's {@code RegisterParticleGroupsEvent} - see {@link KashiParticleClient}), not
 * once per texture. So unlike every earlier generator, this file no longer hands back a render
 * type per effect - {@link #GROUP} is the one shared type every KASHI particle reports from {@code
 * getGroup()}, and {@link KashiParticleGroup}/{@link KashiParticleRenderState} do what used to
 * happen implicitly per-instance: batch by (texture, blend) themselves, using {@link
 * SingleQuadParticle.Layer} as the bucket key - reused as-is from vanilla's own type rather than
 * inventing a parallel one, since it is a public record with a public constructor and already
 * carries exactly (translucent, texture, pipeline).
 *
 * <p>{@link #of} keeps building the pipeline per blend mode the same way the 1.21.8 file did,
 * updated for how a custom blend/depth-write pipeline is actually built now: {@code
 * RenderPipeline.Builder} dropped {@code withBlend}/{@code withDepthWrite} entirely in favour of
 * {@code withColorTargetState(ColorTargetState)}/{@code withDepthStencilState(DepthStencilState)}
 * (confirmed against the real 26.1.2 {@code RenderPipeline}/{@code RenderPipelines} source - the
 * same nested-state shape vanilla's own {@code WEATHER_NO_DEPTH_WRITE} pipeline uses for an
 * identical "keep the blend, drop the depth write" case).
 */
public final class KashiRenderType {

	private KashiRenderType() {
	}

	/**
	 * The one {@link ParticleRenderType} every KASHI particle reports, registered once (see
	 * {@link KashiParticleClient}). Its name never reaches the player - it only has to be a stable
	 * identity the engine can key a single persistent {@link KashiParticleGroup} off of.
	 */
	public static final ParticleRenderType GROUP = new ParticleRenderType("KASHI_PARTICLE_QUADS", "KQ");

	/** Same rationale as the 1.21.8 file: {@link BlendFunction#ADDITIVE} is (ONE, ONE), not
	 * alpha-weighted, which would draw a near-transparent particle at full brightness. Bedrock's
	 * {@code particles_add} material needs (SRC_ALPHA, ONE) instead, built once and shared by every
	 * KASHI effect that uses {@code ADD} - depth write off, or an additive particle would occlude
	 * the ones behind it and the glow would stop accumulating. */
	private static final RenderPipeline ADDITIVE_PIPELINE =
			RenderPipeline.builder(RenderPipelines.PARTICLE_SNIPPET)
					.withLocation("kashi/pipeline/additive_particle")
					.withColorTargetState(new ColorTargetState(new BlendFunction(BlendFactor.SRC_ALPHA, BlendFactor.ONE)))
					.withDepthStencilState(new DepthStencilState(CompareOp.LESS_THAN_OR_EQUAL, false))
					.build();

	private static final Map<String, SingleQuadParticle.Layer> CACHE = new ConcurrentHashMap<>();

	public static SingleQuadParticle.Layer of(Identifier texture, BlendMode blend) {
		return CACHE.computeIfAbsent(texture + "|" + blend, key -> build(texture, blend));
	}

	private static SingleQuadParticle.Layer build(Identifier texture, BlendMode blend) {
		// Vanilla's own particle textures are always the pre-stitched atlas, already uploaded to
		// the GPU at resource-reload time, long before any frame renders. A KASHI effect's own
		// loose PNG has no such guarantee, and this new render model does not allow uploading a
		// texture while a render pass is open (confirmed for real on 26.1.2: "Close the existing
		// render pass before performing additional commands", thrown from inside
		// TextureManager.getTexture() on a texture's first-ever use, mid-render). of() runs during
		// the "extract" phase (KashiParticle.extractQuad, called before any render pass opens for
		// the frame - see KashiParticleGroup), so forcing the load here, once per distinct texture
		// (cached by the CACHE map in of()), guarantees it is already resident by the time anything
		// tries to bind it.
		Minecraft.getInstance().getTextureManager().getTexture(texture);

		RenderPipeline pipeline = switch (blend) {
			// particles_alpha and particles_opaque are alpha *tested*, not blended: with no blend
			// pipeline, the vanilla particle shader's own "discard below 0.1 alpha" is the whole
			// transparency story, which is what gives them their hard edges - reusing vanilla's own
			// opaque particle pipeline verbatim, same as it does for its own particles.
			case CUTOUT, OPAQUE -> RenderPipelines.OPAQUE_PARTICLE;
			// Standard alpha blend, depth write on - exactly what TRANSLUCENT_PARTICLE is.
			case ALPHA -> RenderPipelines.TRANSLUCENT_PARTICLE;
			case ADD -> ADDITIVE_PIPELINE;
		};

		// isTranslucent() used to decide whether the engine sorted these back-to-front; the same
		// role now lives on Layer.translucent() (drives which of the two prepare() passes a layer
		// falls into - see KashiParticleRenderState).
		boolean translucent = blend != BlendMode.CUTOUT && blend != BlendMode.OPAQUE;

		return new SingleQuadParticle.Layer(translucent, texture, pipeline);
	}
}
