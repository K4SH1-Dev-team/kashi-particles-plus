package net.kashi.particles.plugin.element;

import com.google.gson.JsonParser;

import net.kashi.particles.core.KashiParticleDefinition;
import net.kashi.particles.core.KashiParticleParseException;
import net.kashi.particles.core.ParticleDiagnostics;

import net.mcreator.element.parts.TextureHolder;
import net.mcreator.ui.MCreator;
import net.mcreator.ui.dialogs.TypedTextureSelectorDialog;
import net.mcreator.ui.minecraft.TextureSelectionButton;
import net.mcreator.ui.modgui.ModElementGUI;
import net.mcreator.ui.validation.AggregatedValidationResult;
import net.mcreator.ui.workspace.resources.TextureType;
import net.mcreator.workspace.elements.ModElement;

import javax.swing.BorderFactory;
import javax.swing.Box;
import javax.swing.BoxLayout;
import javax.swing.JButton;
import javax.swing.JComponent;
import javax.swing.JFileChooser;
import javax.swing.JLabel;
import javax.swing.JOptionPane;
import javax.swing.JPanel;
import javax.swing.filechooser.FileNameExtensionFilter;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Component;
import java.awt.FlowLayout;
import java.io.File;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import java.util.stream.Collectors;

/**
 * The wizard for a "KASHI Particle" mod element: import a Snowstorm {@code .particle.json} and a
 * texture. The element only fires the effect later; everything about how it looks and moves comes
 * from the JSON, so this wizard configures nothing beyond those two imports.
 *
 * <p>The imported JSON is validated at import time with the very same parser the runtime uses, so a
 * bad file is caught here — with the offending component named — rather than at mod build time.
 */
public class KashiParticleElementGUI extends ModElementGUI<KashiParticleElement> {

	private TextureSelectionButton textureButton;
	private final JLabel jsonStatus = new JLabel();

	/** The raw JSON of the last successfully imported file, or null if none is loaded. */
	private String particleJson;

	public KashiParticleElementGUI(MCreator mcreator, ModElement modElement, boolean editingMode) {
		super(mcreator, modElement, editingMode);

		// MCreator does NOT call initGUI() for us - the subclass constructor must, then finalise.
		// Without this the wizard opens completely empty.
		initGUI();
		finalizeGUI();
	}

	@Override
	protected void initGUI() {
		this.textureButton = new TextureSelectionButton(
				new TypedTextureSelectorDialog(this.mcreator, TextureType.PARTICLE));
		this.textureButton.setOpaque(false);
		this.textureButton.requireValue("A KASHI Particle needs a texture");

		JButton importJson = new JButton("Import .particle.json…");
		importJson.addActionListener(event -> importParticleJson());

		this.jsonStatus.setText("No particle imported yet.");
		this.jsonStatus.setForeground(Color.GRAY);

		JPanel jsonRow = new JPanel(new FlowLayout(FlowLayout.LEFT));
		jsonRow.setOpaque(false);
		jsonRow.add(importJson);
		jsonRow.add(this.jsonStatus);

		JPanel textureRow = new JPanel(new FlowLayout(FlowLayout.LEFT));
		textureRow.setOpaque(false);
		textureRow.add(new JLabel("Particle texture:"));
		textureRow.add(this.textureButton);

		JPanel fields = new JPanel();
		fields.setOpaque(false);
		fields.setLayout(new BoxLayout(fields, BoxLayout.PAGE_AXIS));
		fields.setBorder(BorderFactory.createEmptyBorder(12, 12, 12, 12));
		jsonRow.setAlignmentX(Component.LEFT_ALIGNMENT);
		textureRow.setAlignmentX(Component.LEFT_ALIGNMENT);
		fields.add(jsonRow);
		fields.add(Box.createVerticalStrut(8));
		fields.add(textureRow);

		JComponent page = new JPanel(new BorderLayout());
		page.add(fields, BorderLayout.NORTH);

		addPage("KASHI Particle", page);
	}

	/** Opens a file chooser, then keeps the JSON only if it parses as a Bedrock particle effect. */
	private void importParticleJson() {
		JFileChooser chooser = new JFileChooser();
		chooser.setDialogTitle("Import Snowstorm .particle.json");
		chooser.setFileFilter(new FileNameExtensionFilter("Bedrock particle (*.particle.json, *.json)", "json"));

		if (chooser.showOpenDialog(this.mcreator) != JFileChooser.APPROVE_OPTION)
			return;

		File file = chooser.getSelectedFile();

		try {
			String content = Files.readString(file.toPath(), StandardCharsets.UTF_8);

			// Parse to validate; the result is discarded, we only keep the raw text.
			KashiParticleDefinition definition = KashiParticleDefinition.parse(
					JsonParser.parseString(content).getAsJsonObject());

			this.particleJson = content;
			this.jsonStatus.setText(file.getName() + "  —  " + definition.identifier());
			this.jsonStatus.setForeground(new Color(0x2E7D32));

			showFindings(definition);
		} catch (KashiParticleParseException badEffect) {
			this.particleJson = null;
			this.jsonStatus.setText("Invalid: " + badEffect.getMessage());
			this.jsonStatus.setForeground(new Color(0xC62828));
		} catch (Exception unreadable) {
			this.particleJson = null;
			this.jsonStatus.setText("Could not read file: " + unreadable.getMessage());
			this.jsonStatus.setForeground(new Color(0xC62828));
		}
	}

	/**
	 * Reports what will go wrong with an effect that parsed perfectly well.
	 *
	 * <p>An effect can import without complaint and still draw nothing — zero size, alpha that
	 * never rises, a flipbook running off the end of its sheet — and once it is in the workspace
	 * the only symptom is an empty screen in game, with no clue where to look. Saying it here, next
	 * to the file that was just chosen, is the one moment the author can act on it.
	 *
	 * <p>Never blocks the import: an author is entitled to an effect this cannot make sense of,
	 * and a diagnostic that is wrong must not cost anyone their work.
	 */
	private void showFindings(KashiParticleDefinition definition) {
		List<ParticleDiagnostics.Diagnostic> findings;

		try {
			findings = ParticleDiagnostics.analyse(definition);
		} catch (Exception diagnosticFailed) {
			return;
		}

		List<String> unsupported = definition.unsupported().stream()
				.map(entry -> "• " + entry.component() + " is not implemented: " + entry.impact())
				.collect(Collectors.toList());

		List<String> referenced = definition.referencedEffects();

		if (findings.isEmpty() && unsupported.isEmpty() && referenced.isEmpty())
			return;

		StringBuilder message = new StringBuilder("<html><body style='width: 460px'>");

		message.append("<b>").append(definition.identifier()).append("</b> imported.<br><br>");

		// The one thing about this effect that cannot be seen by looking at it: it is half of a
		// chain, and the other half has to be imported separately or the chain simply stops here.
		if (!referenced.isEmpty()) {
			message.append("This effect starts other effects through its events. Import these too, "
					+ "or nothing will happen where they were meant to appear:<br>");

			referenced.forEach(effect -> message.append("&nbsp;&nbsp;• <b>")
					.append(escape(effect)).append("</b><br>"));

			message.append("<br>");
		}

		for (ParticleDiagnostics.Diagnostic finding : findings) {
			message.append(finding.severity() == ParticleDiagnostics.Severity.ERROR ? "<b>✖ " : "⚠ ")
					.append(escape(finding.message()))
					.append(finding.severity() == ParticleDiagnostics.Severity.ERROR ? "</b>" : "")
					.append("<br><br>");
		}

		unsupported.forEach(entry -> message.append(escape(entry)).append("<br>"));
		message.append("</body></html>");

		boolean severe = findings.stream()
				.anyMatch(finding -> finding.severity() == ParticleDiagnostics.Severity.ERROR);

		JOptionPane.showMessageDialog(this.mcreator, new JLabel(message.toString()),
				severe ? "This effect will not be visible" : "Imported with warnings",
				severe ? JOptionPane.WARNING_MESSAGE : JOptionPane.INFORMATION_MESSAGE);
	}

	private static String escape(String text) {
		return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
	}

	@Override
	protected void openInEditingMode(KashiParticleElement element) {
		this.particleJson = element.particleJson;

		if (element.texture != null)
			this.textureButton.setTexture(element.texture);

		if (this.particleJson != null) {
			this.jsonStatus.setText("Imported particle loaded.");
			this.jsonStatus.setForeground(new Color(0x2E7D32));
		}
	}

	@Override
	public KashiParticleElement getElementFromGUI() {
		KashiParticleElement element = new KashiParticleElement(this.modElement);

		element.particleJson = this.particleJson;
		element.texture = this.textureButton.getTextureHolder();

		return element;
	}

	/**
	 * Blocks saving an element that never got a successfully-imported {@code .particle.json}.
	 *
	 * <p>The texture is already covered - {@code textureButton.requireValue(...)} in
	 * {@link #initGUI()} blocks saving on its own. This is the other half: nothing about the
	 * on-screen state (a label's text) otherwise stops MCreator from happily saving an element
	 * whose {@link KashiParticleElement#particleJson} is null, which would only surface later as
	 * a broken effect in the generated mod. Called from MCreator's own save/finish flow - see
	 * {@code ModElementGUI.finishModCreation()} - so returning FAIL here genuinely blocks the
	 * click, it does not just log a warning.
	 */
	@Override
	protected AggregatedValidationResult getAdditionalValidationResult(KashiParticleElement element) {
		AggregatedValidationResult result = super.getAdditionalValidationResult(element);

		if (!result.validateIsErrorFree())
			return result;

		if (this.particleJson == null)
			return new AggregatedValidationResult.FAIL(
					"A KASHI Particle needs an imported .particle.json before it can be saved.");

		return new AggregatedValidationResult.PASS();
	}

	@Override
	public URI contextURL() throws URISyntaxException {
		return new URI("https://snowstorm.app/");
	}
}
