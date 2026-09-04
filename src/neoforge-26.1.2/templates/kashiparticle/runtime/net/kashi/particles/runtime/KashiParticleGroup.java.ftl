package net.kashi.particles.runtime;

import net.minecraft.CrashReport;
import net.minecraft.CrashReportCategory;
import net.minecraft.ReportedException;

import net.minecraft.client.Camera;
import net.minecraft.client.particle.ParticleEngine;
import net.minecraft.client.particle.ParticleGroup;
import net.minecraft.client.renderer.culling.Frustum;
import net.minecraft.client.renderer.state.level.ParticleGroupRenderState;

/**
 * The NeoForge 26.1.2/26.2 batch every visible {@link KashiParticle} renders through.
 *
 * <p>Registered once, for the whole mod, via {@code RegisterParticleGroupsEvent} in
 * {@link KashiParticleClient} - see {@link KashiRenderType#GROUP} for why every KASHI effect
 * shares this one group instead of one per (texture, blend) the way the render type itself used
 * to work pre-26.1.2. {@link KashiEmitterParticle} never lands here: it reports {@code
 * ParticleRenderType.NO_RENDER} and is handled by vanilla's own no-op group instead.
 *
 * <p>Mirrors vanilla's own {@code QuadParticleGroup} exactly (frustum-cull, then hand each visible
 * particle the shared render state to extract into) - see that class for why the crash-reporting
 * wrapper matters: an effect's MoLang can throw on a genuinely malformed file, and this turns that
 * into a readable in-game crash report naming the effect instead of a silent renderer death.
 */
public final class KashiParticleGroup extends ParticleGroup<KashiParticle> {

	private final KashiParticleRenderState renderState = new KashiParticleRenderState();

	public KashiParticleGroup(ParticleEngine engine) {
		super(engine);
	}

	@Override
	public ParticleGroupRenderState extractRenderState(Frustum frustum, Camera camera, float partialTick) {
		for (KashiParticle particle : this.particles) {
			// A plain point test (what vanilla's own QuadParticleGroup uses) would cull a large
			// quad the moment its centre left the frustum, even with most of it still on screen -
			// see KashiParticle.cullBox() for why this uses the particle's actual extent instead.
			if (!frustum.isVisible(particle.cullBox()))
				continue;

			try {
				particle.extractQuad(this.renderState, camera, partialTick);
			} catch (Throwable t) {
				CrashReport report = CrashReport.forThrowable(t, "Rendering Particle");
				CrashReportCategory category = report.addCategory("Particle being rendered");
				category.setDetail("Particle", particle::toString);
				category.setDetail("Particle Type", this::toString);

				throw new ReportedException(report);
			}
		}

		return this.renderState;
	}
}
