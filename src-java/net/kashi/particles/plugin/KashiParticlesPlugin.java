package net.kashi.particles.plugin;

import net.kashi.particles.plugin.element.KashiParticleElement;
import net.kashi.particles.plugin.element.KashiParticleElementGUI;

import net.mcreator.element.ModElementType;
import net.mcreator.element.ModElementTypeLoader;
import net.mcreator.generator.GeneratorFlavor;
import net.mcreator.plugin.JavaPlugin;
import net.mcreator.plugin.Plugin;
import net.mcreator.plugin.events.PreGeneratorsLoadingEvent;

import java.util.logging.Logger;

/**
 * Entry point for the KASHI Particles Plus MCreator plugin.
 *
 * <p>Declared as {@code javaplugin} in {@code plugin.json}; MCreator instantiates it once at
 * startup, passing the {@link Plugin} descriptor it was loaded from.
 *
 * <p>The "KASHI Particle" element type is registered from a {@link PreGeneratorsLoadingEvent}
 * listener, <b>not</b> from a static initialiser or straight from this constructor. Building a
 * {@link ModElementType} touches MCreator subsystems that are not ready while plugins are still
 * being loaded — doing it too early hangs MCreator on the "Loading plugins" splash. Registering
 * just before generators load is both late enough to be safe and early enough that generators can
 * see the type.
 */
public class KashiParticlesPlugin extends JavaPlugin {

	private static final Logger LOG = Logger.getLogger("KASHI Particles");

	/** The registered "KASHI Particle" element type; null until {@link PreGeneratorsLoadingEvent}. */
	public static ModElementType<?> kashiParticle;

	public KashiParticlesPlugin(Plugin plugin) {
		super(plugin);

		addListener(PreGeneratorsLoadingEvent.class, event -> registerElementTypes());

		LOG.info("KASHI Particles Plus " + plugin.getPluginVersion() + " loaded");
	}

	private static void registerElementTypes() {
		if (kashiParticle != null)
			return;

		// Register FIRST, then declare coverage on the returned instance - the exact order the
		// fusion-geckolib plugin uses. Calling coveredOn before registering risks registering a
		// different instance than the one the coverage lands on.
		kashiParticle = ModElementTypeLoader.register(
				new ModElementType<>("kashiparticle", 'K',
						(mcreator, modElement, editingMode) ->
								new KashiParticleElementGUI(mcreator, modElement, editingMode),
						KashiParticleElement.class))
				.coveredOn(GeneratorFlavor.baseLanguage(GeneratorFlavor.BaseLanguage.JAVA));

		LOG.info("Registered mod element type: " + kashiParticle.getRegistryName());
	}
}
