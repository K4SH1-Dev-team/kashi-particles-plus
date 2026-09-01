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
import javax.swing.JPanel;
import javax.swing.filechooser.FileNameExtensionFilter;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Component;
import java.awt.FlowLayout;
import java.awt.dnd.DnDConstants;
import java.awt.dnd.DropTarget;
import java.awt.dnd.DropTargetAdapter;
import java.awt.dnd.DropTargetDropEvent;
import java.awt.datatransfer.DataFlavor;
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
 * Three sections: <b>Effect</b> (import, by button or drag-and-drop, plus a summary of what was
 * parsed), <b>Diagnostics</b> (kept on screen rather than a popup that closes and is forgotten),
 * and <b>Texture</b> (the texture already renders its own preview - see
 * {@code TextureSelectionButton} - nothing extra needed there).
 */
public class KashiParticleElementGUI extends ModElementGUI<KashiParticleElement> {

	private static final Color OK_COLOR = new Color(0x2E7D32);
	private static final Color ERROR_COLOR = new Color(0xC62828);
	private static final Color MUTED_COLOR = Color.GRAY;

	private TextureSelectionButton textureButton;
	private final JLabel summaryLabel = new JLabel();
	private final JLabel diagnosticsLabel = new JLabel();

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

		resetSummary();
		this.diagnosticsLabel.setText(diagnosticsHtml(null));
		this.diagnosticsLabel.setForeground(MUTED_COLOR);

		JComponent effectSection = titledSection("Effect", effectContent());
		JComponent diagnosticsSection = titledSection("Diagnostics", wrap(this.diagnosticsLabel));
		JComponent textureSection = titledSection("Texture", textureContent());

		JPanel fields = new JPanel();
		fields.setOpaque(false);
		fields.setLayout(new BoxLayout(fields, BoxLayout.PAGE_AXIS));
		fields.setBorder(BorderFactory.createEmptyBorder(12, 12, 12, 12));
		effectSection.setAlignmentX(Component.LEFT_ALIGNMENT);
		diagnosticsSection.setAlignmentX(Component.LEFT_ALIGNMENT);
		textureSection.setAlignmentX(Component.LEFT_ALIGNMENT);
		fields.add(effectSection);
		fields.add(Box.createVerticalStrut(10));
		fields.add(diagnosticsSection);
		fields.add(Box.createVerticalStrut(10));
		fields.add(textureSection);

		JComponent page = new JPanel(new BorderLayout());
		page.add(fields, BorderLayout.NORTH);

		addPage("KASHI Particle", page);
	}

	/** The import button, drop zone and effect summary, stacked. */
	private JComponent effectContent() {
		JButton importJson = new JButton("Import .particle.json…");
		importJson.addActionListener(event -> chooseFile());

		JPanel buttonRow = new JPanel(new FlowLayout(FlowLayout.LEFT));
		buttonRow.setOpaque(false);
		buttonRow.add(importJson);

		JPanel dropZone = new JPanel();
		dropZone.setLayout(new BoxLayout(dropZone, BoxLayout.PAGE_AXIS));
		dropZone.setBorder(BorderFactory.createCompoundBorder(
				BorderFactory.createLineBorder(new Color(0x808080), 1),
				BorderFactory.createEmptyBorder(10, 12, 10, 12)));

		JLabel dropHint = new JLabel("or drag a .particle.json file here");
		dropHint.setForeground(MUTED_COLOR);
		dropHint.setAlignmentX(Component.LEFT_ALIGNMENT);
		this.summaryLabel.setAlignmentX(Component.LEFT_ALIGNMENT);

		dropZone.add(dropHint);
		dropZone.add(Box.createVerticalStrut(6));
		dropZone.add(this.summaryLabel);

		// Plain java.awt.dnd rather than Swing's TransferHandler: a JComponent does not accept
		// drops through a TransferHandler on its own (that machinery is opt-in per component, wired
		// up natively only by components like JList/JTextComponent) - a DropTarget is the one way
		// guaranteed to work on an arbitrary panel like this one.
		new DropTarget(dropZone, new DropTargetAdapter() {
			@Override
			public void drop(DropTargetDropEvent event) {
				event.acceptDrop(DnDConstants.ACTION_COPY);

				try {
					@SuppressWarnings("unchecked")
					List<File> files = (List<File>) event.getTransferable()
							.getTransferData(DataFlavor.javaFileListFlavor);

					if (!files.isEmpty())
						importFile(files.get(0));

					event.dropComplete(true);
				} catch (Exception dropFailed) {
					event.dropComplete(false);
				}
			}
		});

		JPanel content = new JPanel();
		content.setOpaque(false);
		content.setLayout(new BoxLayout(content, BoxLayout.PAGE_AXIS));
		buttonRow.setAlignmentX(Component.LEFT_ALIGNMENT);
		dropZone.setAlignmentX(Component.LEFT_ALIGNMENT);
		content.add(buttonRow);
		content.add(Box.createVerticalStrut(6));
		content.add(dropZone);

		return content;
	}

	private JComponent textureContent() {
		JPanel textureRow = new JPanel(new FlowLayout(FlowLayout.LEFT));
		textureRow.setOpaque(false);
		textureRow.add(new JLabel("Particle texture:"));
		textureRow.add(this.textureButton);

		return textureRow;
	}

	private static JComponent titledSection(String title, JComponent content) {
		JPanel section = new JPanel(new BorderLayout());
		section.setOpaque(false);
		section.setBorder(BorderFactory.createCompoundBorder(
				BorderFactory.createTitledBorder(title),
				BorderFactory.createEmptyBorder(4, 6, 6, 6)));
		section.add(content, BorderLayout.CENTER);

		return section;
	}

	private static JComponent wrap(JComponent content) {
		JPanel wrapper = new JPanel(new FlowLayout(FlowLayout.LEFT));
		wrapper.setOpaque(false);
		wrapper.add(content);

		return wrapper;
	}

	/** Opens a file chooser, then hands the pick to {@link #importFile(File)}. */
	private void chooseFile() {
		JFileChooser chooser = new JFileChooser();
		chooser.setDialogTitle("Import Snowstorm .particle.json");
		chooser.setFileFilter(new FileNameExtensionFilter("Bedrock particle (*.particle.json, *.json)", "json"));

		if (chooser.showOpenDialog(this.mcreator) == JFileChooser.APPROVE_OPTION)
			importFile(chooser.getSelectedFile());
	}

	/**
	 * Parses {@code file} and keeps it only if it parses as a Bedrock particle effect - shared by
	 * the file chooser and drag-and-drop, so both paths behave identically.
	 */
	private void importFile(File file) {
		try {
			String content = Files.readString(file.toPath(), StandardCharsets.UTF_8);

			// Parse to validate; the result is discarded, we only keep the raw text.
			KashiParticleDefinition definition = KashiParticleDefinition.parse(
					JsonParser.parseString(content).getAsJsonObject());

			this.particleJson = content;
			updateSummary(file.getName(), definition);
			updateDiagnostics(definition);
		} catch (KashiParticleParseException badEffect) {
			this.particleJson = null;
			this.summaryLabel.setText("<html>Invalid: " + escape(badEffect.getMessage()) + "</html>");
			this.summaryLabel.setForeground(ERROR_COLOR);
			this.diagnosticsLabel.setText(diagnosticsHtml(null));
			this.diagnosticsLabel.setForeground(MUTED_COLOR);
		} catch (Exception unreadable) {
			this.particleJson = null;
			this.summaryLabel.setText("<html>Could not read file: " + escape(unreadable.getMessage()) + "</html>");
			this.summaryLabel.setForeground(ERROR_COLOR);
			this.diagnosticsLabel.setText(diagnosticsHtml(null));
			this.diagnosticsLabel.setForeground(MUTED_COLOR);
		}
	}

	private void resetSummary() {
		this.summaryLabel.setText("<html>No particle imported yet.</html>");
		this.summaryLabel.setForeground(MUTED_COLOR);
	}

	/** A few key facts about the parsed effect, in place of the old one-line filename+identifier. */
	private void updateSummary(String fileName, KashiParticleDefinition definition) {
		StringBuilder html = new StringBuilder("<html><body style='width: 360px'>");

		html.append(escape(fileName)).append("<br>");
		html.append("<b>").append(escape(definition.identifier())).append("</b><br>");
		html.append("Material: ").append(escape(definition.render().material()))
				.append(" (").append(definition.render().blend()).append(")<br>");
		html.append("Lifetime: ").append(lifetimeKind(definition));

		if (!definition.unsupported().isEmpty())
			html.append("<br>").append(definition.unsupported().size()).append(" component(s) not implemented");

		if (!definition.referencedEffects().isEmpty())
			html.append("<br>References ").append(definition.referencedEffects().size())
					.append(" other effect(s) - see Diagnostics");

		html.append("</body></html>");

		this.summaryLabel.setText(html.toString());
		this.summaryLabel.setForeground(OK_COLOR);
	}

	private static String lifetimeKind(KashiParticleDefinition definition) {
		return switch (definition.lifetime()) {
			case KashiParticleDefinition.EmitterLifetime.Once ignored -> "once";
			case KashiParticleDefinition.EmitterLifetime.Looping ignored -> "looping";
			case KashiParticleDefinition.EmitterLifetime.Expression ignored -> "expression-driven";
		};
	}

	/**
	 * Reports what will go wrong with an effect that parsed perfectly well.
	 *
	 * <p>An effect can import without complaint and still draw nothing — zero size, alpha that
	 * never rises, a flipbook running off the end of its sheet — and once it is in the workspace
	 * the only symptom is an empty screen in game, with no clue where to look. Saying it here, next
	 * to the file that was just chosen, is the one moment the author can act on it. Stays on screen
	 * in the Diagnostics section rather than a dialog, so it is still there if the author looks
	 * back after fiddling with the texture field.
	 *
	 * <p>Never blocks the import: an author is entitled to an effect this cannot make sense of,
	 * and a diagnostic that is wrong must not cost anyone their work.
	 */
	private void updateDiagnostics(KashiParticleDefinition definition) {
		List<ParticleDiagnostics.Diagnostic> findings;

		try {
			findings = ParticleDiagnostics.analyse(definition);
		} catch (Exception diagnosticFailed) {
			this.diagnosticsLabel.setText(diagnosticsHtml(null));
			this.diagnosticsLabel.setForeground(MUTED_COLOR);
			return;
		}

		List<String> unsupported = definition.unsupported().stream()
				.map(entry -> "• " + entry.component() + " is not implemented: " + entry.impact())
				.collect(Collectors.toList());

		List<String> referenced = definition.referencedEffects();

		boolean severe = findings.stream()
				.anyMatch(finding -> finding.severity() == ParticleDiagnostics.Severity.ERROR);

		this.diagnosticsLabel.setText(diagnosticsHtml(
				buildDiagnosticsBody(findings, unsupported, referenced)));
		this.diagnosticsLabel.setForeground(severe ? ERROR_COLOR
				: findings.isEmpty() && unsupported.isEmpty() && referenced.isEmpty() ? OK_COLOR : ERROR_COLOR);
	}

	/** Null (or an effectively empty body) means "nothing to report". */
	private String buildDiagnosticsBody(List<ParticleDiagnostics.Diagnostic> findings,
			List<String> unsupported, List<String> referenced) {
		if (findings.isEmpty() && unsupported.isEmpty() && referenced.isEmpty())
			return null;

		StringBuilder body = new StringBuilder();

		// The one thing about this effect that cannot be seen by looking at it: it is half of a
		// chain, and the other half has to be imported separately or the chain simply stops here.
		if (!referenced.isEmpty()) {
			body.append("This effect starts other effects through its events. Import these too, "
					+ "or nothing will happen where they were meant to appear:<br>");

			referenced.forEach(effect -> body.append("&nbsp;&nbsp;• <b>")
					.append(escape(effect)).append("</b><br>"));

			body.append("<br>");
		}

		for (ParticleDiagnostics.Diagnostic finding : findings) {
			body.append(finding.severity() == ParticleDiagnostics.Severity.ERROR ? "<b>✖ " : "⚠ ")
					.append(escape(finding.message()))
					.append(finding.severity() == ParticleDiagnostics.Severity.ERROR ? "</b>" : "")
					.append("<br><br>");
		}

		unsupported.forEach(entry -> body.append(escape(entry)).append("<br>"));

		return body.toString();
	}

	private static String diagnosticsHtml(String body) {
		String content = body == null || body.isBlank()
				? "No issues found - this effect should play as authored."
				: body;

		return "<html><body style='width: 420px'>" + content + "</body></html>";
	}

	private static String escape(String text) {
		return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
	}

	@Override
	protected void openInEditingMode(KashiParticleElement element) {
		this.particleJson = element.particleJson;

		if (element.texture != null)
			this.textureButton.setTexture(element.texture);

		if (this.particleJson == null) {
			resetSummary();
			this.diagnosticsLabel.setText(diagnosticsHtml(null));
			this.diagnosticsLabel.setForeground(MUTED_COLOR);
			return;
		}

		// Re-parse the saved JSON so a reopened element shows the same summary and diagnostics a
		// fresh import would - not just a generic "loaded" message. This was already validated at
		// save time (getAdditionalValidationResult below), so a parse failure here would mean the
		// file on disk was hand-edited after saving; fall back to a plain notice rather than
		// letting the wizard throw while opening.
		try {
			KashiParticleDefinition definition = KashiParticleDefinition.parse(
					JsonParser.parseString(this.particleJson).getAsJsonObject());

			updateSummary("(saved effect)", definition);
			updateDiagnostics(definition);
		} catch (Exception unreadable) {
			this.summaryLabel.setText("<html>Imported particle loaded.</html>");
			this.summaryLabel.setForeground(OK_COLOR);
			this.diagnosticsLabel.setText(diagnosticsHtml(null));
			this.diagnosticsLabel.setForeground(MUTED_COLOR);
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
