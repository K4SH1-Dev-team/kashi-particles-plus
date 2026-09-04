<#--
	Generated registry of every KASHI Particle element in the workspace.

	One line per imported effect, pairing the .particle.json emitted next to it with the texture the
	user picked in the wizard. Regenerated whenever elements change, so adding a KASHI Particle in
	MCreator is all it takes for the effect to exist in game - no code to write.

	This is the NeoForge 26.1.2/26.2 variant of this file - the ONLY difference from 1.21.1/1.21.8's
	is ResourceLocation -> Identifier (see docs/ARCHITECTURE.md). This file was missed entirely when
	those two generators' folders were first set up (only particle.json.ftl was copied over, not
	this one) - MCreator degrades a missing global_template silently rather than failing the build,
	so the symptom was not a compile error but every effect failing to register at all (registerAll()
	never got regenerated from the workspace's dev placeholder stub, which does nothing). Caught only
	by an actual in-game test finding nothing fired, not by any build step - keep this in mind if a
	generator's registerAll() ever mysteriously does nothing again.
-->
package net.kashi.particles.runtime;

import net.minecraft.resources.Identifier;

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
		Identifier id = Identifier.fromNamespaceAndPath(KashiParticlesRuntime.MODID, name);

		if (KashiParticleRegistry.contains(id))
			return;

		try {
			KashiParticleRegistry.loadFromClasspath(id,
					"/assets/" + KashiParticlesRuntime.MODID + "/kashi_particles/" + name + ".particle.json",
					Identifier.fromNamespaceAndPath(KashiParticlesRuntime.MODID,
							"textures/particle/" + texture + ".png"));
		} catch (RuntimeException broken) {
			// One unloadable effect must not take the others - or the particle provider itself -
			// down with it. Report it and carry on; only that effect goes missing.
			org.slf4j.LoggerFactory.getLogger("KASHI Particles")
					.error("Could not load KASHI particle '{}'; it will not play.", name, broken);
		}
	}
}
