<#--
	Generated registry of every KASHI Particle element in the workspace.

	One line per imported effect, pairing the .particle.json emitted next to it with the texture the
	user picked in the wizard. Regenerated whenever elements change, so adding a KASHI Particle in
	MCreator is all it takes for the effect to exist in game - no code to write.
-->
package net.kashi.particles.runtime;

import net.minecraft.resources.ResourceLocation;

/**
 * Every KASHI Particle effect imported into this mod.
 *
 * <p>Generated from the workspace's "KASHI Particle" elements - do not edit by hand; changes are
 * overwritten on the next build.
 */
public final class KashiParticleEffects {

	private KashiParticleEffects() {
	}

	/** Parses and registers every imported effect. Called once, client-side, at start-up. */
	public static void registerAll() {
<#list w.getGElementsOfType("kashiparticle") as effect>
		register("${effect.getModElement().getRegistryName()}", "${effect.texture}");
</#list>
	}

	private static void register(String name, String texture) {
		ResourceLocation id = ResourceLocation.fromNamespaceAndPath(KashiParticlesRuntime.MODID, name);

		if (KashiParticleRegistry.contains(id))
			return;

		try {
			KashiParticleRegistry.loadFromClasspath(id,
					"/assets/" + KashiParticlesRuntime.MODID + "/kashi_particles/" + name + ".particle.json",
					ResourceLocation.fromNamespaceAndPath(KashiParticlesRuntime.MODID,
							"textures/particle/" + texture + ".png"));
		} catch (RuntimeException broken) {
			// One unloadable effect must not take the others - or the particle provider itself -
			// down with it. Report it and carry on; only that effect goes missing.
			org.slf4j.LoggerFactory.getLogger("KASHI Particles")
					.error("Could not load KASHI particle '{}'; it will not play.", name, broken);
		}
	}
}
