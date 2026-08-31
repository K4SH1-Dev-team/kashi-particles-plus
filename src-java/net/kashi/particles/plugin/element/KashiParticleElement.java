package net.kashi.particles.plugin.element;

import net.mcreator.element.GeneratableElement;
import net.mcreator.element.parts.TextureHolder;
import net.mcreator.workspace.elements.ModElement;

/**
 * The data of one "KASHI Particle" mod element: an imported Snowstorm {@code .particle.json} and
 * the texture it draws with.
 *
 * <p>MCreator serialises these public fields to the workspace via Gson, so the element survives
 * save/load. Nothing here parses or renders — the imported JSON is kept verbatim and handed to the
 * runtime at generation time; the wizard only validates that it parses before letting it be saved.
 */
@SuppressWarnings("unused")
public class KashiParticleElement extends GeneratableElement {

	/** The raw contents of the imported {@code .particle.json}, stored as-is. */
	public String particleJson;

	/** The particle texture imported into the workspace. */
	public TextureHolder texture;

	public KashiParticleElement(ModElement element) {
		super(element);
	}
}
