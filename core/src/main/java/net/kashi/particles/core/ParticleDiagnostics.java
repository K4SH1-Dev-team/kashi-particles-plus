package net.kashi.particles.core;

import net.kashi.particles.core.molang.MolangCompiler;
import net.kashi.particles.core.molang.MolangContext;
import net.kashi.particles.core.molang.MolangContext.Var;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Answers "it plays in Snowstorm but nothing shows in game" without launching the game.
 *
 * <p>An effect that parses cleanly can still be invisible, and the reasons are few and dull: it is
 * zero-sized, its alpha never rises off the floor, its particles expire before they are drawn, or
 * its flipbook claims more frames than the texture sheet holds. Each of those is decidable from the
 * definition alone, so this walks a representative particle through its life and reports them.
 *
 * <p>Findings are advisory. Nothing here rejects an effect — an author is entitled to a deliberately
 * invisible particle, and a warning that cannot be silenced is worse than no warning.
 */
public final class ParticleDiagnostics {

	private ParticleDiagnostics() {
	}

	/** How much a finding matters: {@code ERROR} means the effect will show nothing at all. */
	public enum Severity { ERROR, WARNING }

	/**
	 * @param code a short stable identifier, so callers can group or filter findings without
	 *             matching on prose
	 */
	public record Diagnostic(Severity severity, String code, String message) {

		@Override
		public String toString() {
			return this.severity + " [" + this.code + "] " + this.message;
		}
	}

	/** How many points across a particle's life are sampled before calling something constant. */
	private static final int SAMPLES = 21;

	/** How many times a single random-bearing expression is drawn before believing its value. */
	private static final int DRAWS = 12;

	/**
	 * Matches {@code KashiEmitterParticle.MAX_LOOPING_SECONDS}: a looping or expression-driven
	 * emitter has no natural end, so the runtime bounds it and this estimate must bound it the
	 * same way or it would predict an effect running forever.
	 */
	private static final double MAX_LOOPING_SECONDS = 30;

	/**
	 * Above this many particles over an effect's full run, an author gets a heads-up rather than
	 * discovering it as a frame-rate cliff later - particularly the ones that fire several such
	 * effects in the same tick (an AOE hitting a crowd, a burst of test items), where a few
	 * thousand each compounds fast. Picked from the pack this was built against: most effects stay
	 * under a few hundred, and a handful reach into the tens of thousands by design (a lingering
	 * cloud, a long trail) - 2000 sits above ordinary effects without staying quiet about the ones
	 * actually worth knowing about before shipping.
	 */
	private static final double HEAVY_PARTICLE_COUNT = 2000;

	public static List<Diagnostic> analyse(KashiParticleDefinition definition) {
		List<Diagnostic> found = new ArrayList<>();
		MolangCompiler compiler = new MolangCompiler();
		List<String> sources = sources(definition);

		undefinedVariables(definition, sources, found);

		// Parsing keeps expressions as raw text, so a malformed one survives the import and only
		// fails when the mod compiles it at registration - which is a crash on world load rather
		// than a note in the wizard. Compiling every one of them here moves that to now.
		if (invalidExpressions(sources, compiler, found))
			return found;

		MolangContext context = compiler.newContext();

		context.set(Var.EMITTER_AGE, 0);
		context.set(Var.PARTICLE_AGE, 0);
		context.set(Var.PARTICLE_RANDOM_1, 0.5);
		context.set(Var.PARTICLE_RANDOM_2, 0.5);
		context.set(Var.PARTICLE_RANDOM_3, 0.5);
		context.set(Var.PARTICLE_RANDOM_4, 0.5);
		context.set(Var.EMITTER_RANDOM_1, 0.5);
		context.set(Var.EMITTER_RANDOM_2, 0.5);
		context.set(Var.EMITTER_RANDOM_3, 0.5);
		context.set(Var.EMITTER_RANDOM_4, 0.5);

		// The same order the runtime uses: an effect that defines its variables in an
		// initialization expression must have them defined before anything reads them, or every
		// check below would measure zeroes that the real runtime never sees.
		if (definition.emitterInit() != null)
			eval(compiler, context, definition.emitterInit().creation());

		// Drawn several times, not once: max_lifetime is usually a math.random, which re-rolls on
		// every evaluation. A single unlucky draw would report an effect as broken on one run and
		// fine on the next.
		double life = 0;

		for (int draw = 0; draw < DRAWS; draw++)
			life = Math.max(life, eval(compiler, context, definition.particleLifetime().maxLifetime()));

		context.set(Var.PARTICLE_LIFETIME, life);
		context.set(Var.EMITTER_LIFETIME, emitterActiveTime(definition, compiler, context));

		if (life <= 0) {
			found.add(new Diagnostic(Severity.ERROR, "lifetime-zero",
					"particles expire the instant they are born - max_lifetime is '"
							+ definition.particleLifetime().maxLifetime().source()
							+ "', which never evaluates above zero"));
		}

		emitterFindings(definition, compiler, context, found);
		lifeFindings(definition, compiler, context, life, found);
		flipbookFindings(definition, compiler, context, life, found);
		volumeFindings(definition, compiler, context, found);

		return found;
	}

	// -------------------------------------------------------------- the checks

	private static void emitterFindings(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context, List<Diagnostic> found) {
		switch (definition.rate()) {
			case KashiParticleDefinition.EmitterRate.Instant instant -> {
				if (eval(compiler, context, instant.numParticles()) < 1)
					found.add(new Diagnostic(Severity.ERROR, "spawns-nothing",
							"an instant emitter that spawns fewer than one particle"));
			}
			case KashiParticleDefinition.EmitterRate.Steady steady -> {
				if (eval(compiler, context, steady.spawnRate()) <= 0)
					found.add(new Diagnostic(Severity.ERROR, "spawns-nothing",
							"a steady emitter with a spawn_rate of zero"));

				if (eval(compiler, context, steady.maxParticles()) < 1)
					found.add(new Diagnostic(Severity.ERROR, "spawns-nothing",
							"max_particles is below one, so nothing may be alive at a time"));
			}
			case KashiParticleDefinition.EmitterRate.Manual manual -> { }
		}

		if (definition.lifetime() instanceof KashiParticleDefinition.EmitterLifetime.Once once
				&& eval(compiler, context, once.activeTime()) <= 0) {
			found.add(new Diagnostic(Severity.WARNING, "emitter-instant",
					"the emitter's active_time is zero, so it only gets the one tick to emit"));
		}
	}

	/**
	 * Walks the particle through its life, looking for the two properties that must be non-zero at
	 * some point for anything to appear on screen: a size and an alpha.
	 */
	private static void lifeFindings(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context, double life, List<Diagnostic> found) {
		double peakSize = 0;
		double peakAlpha = 0;

		for (int i = 0; i < SAMPLES; i++) {
			double age = life * i / (SAMPLES - 1.0);

			context.set(Var.PARTICLE_AGE, age);
			context.set(Var.EMITTER_AGE, age);
			applyCurves(definition, compiler, context);

			if (definition.particleInit() != null)
				eval(compiler, context, definition.particleInit().perUpdate());

			double width = Math.abs(eval(compiler, context, definition.appearance().size().x()));
			double height = Math.abs(eval(compiler, context, definition.appearance().size().y()));

			peakSize = Math.max(peakSize, Math.min(width, height));
			peakAlpha = Math.max(peakAlpha, alphaAt(definition, compiler, context));
		}

		if (peakSize <= 0) {
			found.add(new Diagnostic(Severity.ERROR, "size-zero",
					"the particle has no size at any point in its life, so nothing is drawn"));
		}

		if (peakAlpha <= 0.01) {
			found.add(new Diagnostic(Severity.ERROR, "alpha-zero",
					"alpha never rises above zero - the particle is fully transparent throughout"));
		}
	}

	/**
	 * Checks the flipbook against the sheet it reads from.
	 *
	 * <p>{@code max_frame} is authored by hand and nothing in Bedrock cross-checks it, so a sheet
	 * that was shortened after the effect was written leaves the tail of the animation sampling
	 * empty space — the effect plays, then silently blanks out partway through.
	 */
	private static void flipbookFindings(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context, double life, List<Diagnostic> found) {
		KashiParticleDefinition.Uv sheet = definition.appearance().uv();
		KashiParticleDefinition.Flipbook flipbook = sheet.flipbook();

		if (flipbook == null)
			return;

		context.set(Var.PARTICLE_AGE, 0);
		applyCurves(definition, compiler, context);

		double stepX = eval(compiler, context, flipbook.stepUv().x());
		double stepY = eval(compiler, context, flipbook.stepUv().y());
		double sizeX = eval(compiler, context, flipbook.sizeUv().x());
		double sizeY = eval(compiler, context, flipbook.sizeUv().y());

		if (sizeX <= 0 || sizeY <= 0) {
			found.add(new Diagnostic(Severity.ERROR, "uv-zero",
					"the flipbook's size_UV is zero, so every frame samples nothing"));

			return;
		}

		// Frames advance along whichever axis the step uses; a zero step is a still image.
		double available = Double.MAX_VALUE;

		if (stepX > 0)
			available = Math.min(available, Math.floor((sheet.textureWidth() - sizeX) / stepX) + 1);

		if (stepY > 0)
			available = Math.min(available, Math.floor((sheet.textureHeight() - sizeY) / stepY) + 1);

		// One frame over is the normal way to author a stretched flipbook, not a mistake: the frame
		// index only reaches max_frame at the exact instant the particle dies, so a sheet of N
		// frames is written as max_frame = N + 1 to make all N play across the lifetime. Warning
		// about that would bury the real cases in noise.
		if (available != Double.MAX_VALUE && flipbook.maxFrame() > available + 1) {
			found.add(new Diagnostic(Severity.WARNING, "max-frame-past-sheet", String.format(Locale.ROOT,
					"max_frame is %.0f but the %.0fx%.0f sheet only holds %.0f frames at this "
							+ "step - the last %.0f sample past its edge and show nothing",
					flipbook.maxFrame(), sheet.textureWidth(), sheet.textureHeight(), available,
					flipbook.maxFrame() - available)));
		}

		if (!flipbook.stretchToLifetime()) {
			double fps = eval(compiler, context, flipbook.fps());

			if (fps > 0 && !flipbook.loop() && flipbook.maxFrame() / fps < life * 0.5) {
				found.add(new Diagnostic(Severity.WARNING, "animation-ends-early", String.format(Locale.ROOT,
						"the animation finishes after %.2fs but the particle lives %.2fs, so it "
								+ "holds its last frame for the rest", flipbook.maxFrame() / fps, life)));
			}
		}
	}

	/**
	 * Finds {@code variable.*} names that are read but never written.
	 *
	 * <p>A misspelt variable is not an error in MoLang — it reads as zero — so it surfaces as a
	 * particle that is the wrong size, or invisible, with nothing to point at. Matching on the raw
	 * expression text is coarse but catches the case that matters: a name that appears nowhere as
	 * an assignment target and has no curve to define it.
	 */
	private static void undefinedVariables(KashiParticleDefinition definition, List<String> sources,
			List<Diagnostic> found) {
		Set<String> read = new LinkedHashSet<>();
		Set<String> written = new LinkedHashSet<>();

		for (KashiParticleDefinition.Curve curve : definition.curves())
			written.add(canonical(curve.variable()));

		for (String source : sources) {
			Matcher matcher = VARIABLE.matcher(source);

			while (matcher.find()) {
				String name = canonical(matcher.group());

				// An assignment is the name followed by a single '=', never '=='.
				if (source.startsWith("=", skipSpaces(source, matcher.end()))
						&& !source.startsWith("==", skipSpaces(source, matcher.end()))) {
					written.add(name);
				} else {
					read.add(name);
				}
			}
		}

		read.removeAll(written);
		read.removeIf(ParticleDiagnostics::isBuiltIn);

		for (String name : read) {
			found.add(new Diagnostic(Severity.WARNING, "variable-undefined",
					"'" + name + "' is read but never set by a curve or an initialization "
							+ "expression, so it evaluates to zero"));
		}
	}

	/** @return whether anything failed to compile, in which case evaluating would only repeat it */
	private static boolean invalidExpressions(List<String> sources, MolangCompiler compiler,
			List<Diagnostic> found) {
		Set<String> reported = new LinkedHashSet<>();

		for (String source : sources) {
			try {
				compiler.compile(source);
			} catch (RuntimeException malformed) {
				// One malformed expression is usually copied across several fields; report the
				// text once rather than once per field.
				if (reported.add(source)) {
					found.add(new Diagnostic(Severity.ERROR, "expression-invalid",
							"'" + source + "' is not valid MoLang and will fail when the mod loads: "
									+ firstLine(malformed.getMessage())));
				}
			}
		}

		return !reported.isEmpty();
	}

	private static String firstLine(String message) {
		if (message == null)
			return "no detail";

		int newline = message.indexOf('\n');

		return newline < 0 ? message : message.substring(0, newline);
	}

	// ---------------------------------------------------------------- helpers

	private static final Pattern VARIABLE = Pattern.compile("\\b(v|variable)\\.([a-zA-Z_][a-zA-Z0-9_]*)");

	private static String canonical(String name) {
		String lower = name.toLowerCase(Locale.ROOT);

		return lower.startsWith("v.") ? "variable." + lower.substring(2) : lower;
	}

	private static boolean isBuiltIn(String canonicalName) {
		for (Var variable : Var.values()) {
			if (canonicalName.equals(variable.canonicalName()))
				return true;
		}

		return false;
	}

	private static int skipSpaces(String source, int from) {
		int i = from;

		while (i < source.length() && Character.isWhitespace(source.charAt(i)))
			i++;

		return i;
	}

	/** Every MoLang source in the effect, so a name can be searched for across all of them. */
	private static List<String> sources(KashiParticleDefinition definition) {
		List<String> sources = new ArrayList<>();

		definition.curves().forEach(curve -> {
			sources.add(curve.input().source());
			sources.add(curve.horizontalRange().source());
		});

		if (definition.emitterInit() != null) {
			sources.add(definition.emitterInit().creation().source());
			sources.add(definition.emitterInit().perUpdate().source());
		}

		if (definition.particleInit() != null) {
			sources.add(definition.particleInit().perUpdate().source());
			sources.add(definition.particleInit().perRender().source());
		}

		sources.add(definition.particleLifetime().maxLifetime().source());
		sources.add(definition.particleLifetime().expiration().source());
		sources.add(definition.appearance().size().x().source());
		sources.add(definition.appearance().size().y().source());

		switch (definition.rate()) {
			case KashiParticleDefinition.EmitterRate.Steady steady -> {
				sources.add(steady.spawnRate().source());
				sources.add(steady.maxParticles().source());
			}
			case KashiParticleDefinition.EmitterRate.Instant instant ->
					sources.add(instant.numParticles().source());
			case KashiParticleDefinition.EmitterRate.Manual manual ->
					sources.add(manual.maxParticles().source());
		}

		switch (definition.lifetime()) {
			case KashiParticleDefinition.EmitterLifetime.Once once ->
					sources.add(once.activeTime().source());
			case KashiParticleDefinition.EmitterLifetime.Looping looping -> {
				sources.add(looping.activeTime().source());
				sources.add(looping.sleepTime().source());
			}
			case KashiParticleDefinition.EmitterLifetime.Expression expression -> {
				sources.add(expression.activation().source());
				sources.add(expression.expiration().source());
			}
		}

		vec3(definition.shape().offset(), sources);
		shapeSources(definition.shape(), sources);

		if (definition.motionParametric() != null) {
			vec3(definition.motionParametric().relativePosition(), sources);
			vec3(definition.motionParametric().direction(), sources);
			sources.add(definition.motionParametric().rotation().source());
		}

		if (definition.tinting() != null && definition.tinting().color() != null) {
			sources.add(definition.tinting().color().r().source());
			sources.add(definition.tinting().color().g().source());
			sources.add(definition.tinting().color().b().source());
			sources.add(definition.tinting().color().a().source());
		}

		switch (definition.initialSpeed()) {
			case KashiParticleDefinition.InitialSpeed.AlongDirection along ->
					sources.add(along.speed().source());
			case KashiParticleDefinition.InitialSpeed.Velocity explicit ->
					vec3(explicit.velocity(), sources);
			case null -> { }
		}

		if (definition.initialSpin() != null) {
			sources.add(definition.initialSpin().rotation().source());
			sources.add(definition.initialSpin().rotationRate().source());
		}

		if (definition.motion() != null) {
			vec3(definition.motion().linearAcceleration(), sources);
			sources.add(definition.motion().linearDrag().source());
		}

		if (definition.tinting() != null && definition.tinting().interpolant() != null)
			sources.add(definition.tinting().interpolant().source());

		KashiParticleDefinition.Flipbook flipbook = definition.appearance().uv().flipbook();

		if (flipbook != null) {
			sources.add(flipbook.baseUv().x().source());
			sources.add(flipbook.baseUv().y().source());
			sources.add(flipbook.stepUv().x().source());
			sources.add(flipbook.sizeUv().x().source());
			sources.add(flipbook.fps().source());
		}

		sources.removeIf(source -> source == null || source.isBlank());

		return sources;
	}

	private static void shapeSources(KashiParticleDefinition.EmitterShape shape, List<String> sources) {
		switch (shape) {
			case KashiParticleDefinition.EmitterShape.Sphere sphere -> {
				sources.add(sphere.radius().source());
				directionSources(sphere.direction(), sources);
			}
			case KashiParticleDefinition.EmitterShape.Box box -> {
				vec3(box.halfDimensions(), sources);
				directionSources(box.direction(), sources);
			}
			case KashiParticleDefinition.EmitterShape.Disc disc -> {
				vec3(disc.planeNormal(), sources);
				sources.add(disc.radius().source());
				directionSources(disc.direction(), sources);
			}
			case KashiParticleDefinition.EmitterShape.Point point ->
					directionSources(point.direction(), sources);
			case KashiParticleDefinition.EmitterShape.EntityAabb aabb ->
					directionSources(aabb.direction(), sources);
		}
	}

	private static void directionSources(KashiParticleDefinition.EmitterDirection direction,
			List<String> sources) {
		if (direction instanceof KashiParticleDefinition.EmitterDirection.Custom custom)
			vec3(custom.vector(), sources);
	}

	private static void vec3(KashiParticleDefinition.Vec3Expr vec, List<String> sources) {
		sources.add(vec.x().source());
		sources.add(vec.y().source());
		sources.add(vec.z().source());
	}

	private static void applyCurves(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context) {
		for (KashiParticleDefinition.Curve curve : definition.curves()) {
			double range = eval(compiler, context, curve.horizontalRange());
			double position = range == 0 ? 0 : eval(compiler, context, curve.input()) / range;

			if (!Double.isFinite(position))
				position = 0;

			double value = curve.chain() != null
					? CurveSampler.sampleChain(position, curve.chain())
					: CurveSampler.sample(curve.type(), position, curve.nodes());

			context.setVariable(compiler.slotOf(curve.variable()), value);
		}
	}

	/**
	 * Estimates how many particles one full run of this effect spawns, so an author can see "this
	 * one effect is 18,000 particles" before that surprises them as a frame drop - especially once
	 * several such effects fire in the same tick, which compounds fast and is exactly what a KASHI
	 * spawn invites (an AOE, a crowd of enemies each playing their own hit effect).
	 *
	 * <p>Worst case, not typical case: a {@code Steady} rate is read as running for its whole
	 * active time at the sampled spawn_rate, not accounting for max_particles ever throttling it
	 * down - the point is an upper bound worth knowing about, not a precise simulation.
	 */
	private static double estimateTotalParticles(KashiParticleDefinition definition,
			MolangCompiler compiler, MolangContext context) {
		double runSeconds = switch (definition.lifetime()) {
			case KashiParticleDefinition.EmitterLifetime.Once once ->
					eval(compiler, context, once.activeTime());
			case KashiParticleDefinition.EmitterLifetime.Looping looping ->
					Math.min(MAX_LOOPING_SECONDS,
							eval(compiler, context, looping.activeTime())
									+ eval(compiler, context, looping.sleepTime()));
			case KashiParticleDefinition.EmitterLifetime.Expression expression -> MAX_LOOPING_SECONDS;
		};

		boolean loops = !(definition.lifetime() instanceof KashiParticleDefinition.EmitterLifetime.Once);

		return switch (definition.rate()) {
			case KashiParticleDefinition.EmitterRate.Instant instant -> {
				double perBurst = Math.max(0, eval(compiler, context, instant.numParticles()));

				if (!loops)
					yield perBurst;

				double cycle = switch (definition.lifetime()) {
					case KashiParticleDefinition.EmitterLifetime.Looping looping ->
							eval(compiler, context, looping.activeTime())
									+ eval(compiler, context, looping.sleepTime());
					default -> 1;
				};

				yield perBurst * Math.max(1, Math.floor(MAX_LOOPING_SECONDS / Math.max(cycle, 0.05)));
			}
			case KashiParticleDefinition.EmitterRate.Steady steady ->
					Math.max(0, eval(compiler, context, steady.spawnRate())) * Math.max(0, runSeconds);
			case KashiParticleDefinition.EmitterRate.Manual manual -> 0; // only ever emits on request
		};
	}

	private static void volumeFindings(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context, List<Diagnostic> found) {
		double total = estimateTotalParticles(definition, compiler, context);

		if (total > HEAVY_PARTICLE_COUNT) {
			found.add(new Diagnostic(Severity.WARNING, "particle-volume-heavy", String.format(Locale.ROOT,
					"one full run of this effect spawns roughly %.0f particles - fine on its own, "
							+ "but firing several such effects in the same tick (an AOE, a crowd) "
							+ "adds up fast; consider whether every caller of this effect needs to",
					total)));
		}
	}

	private static double emitterActiveTime(KashiParticleDefinition definition,
			MolangCompiler compiler, MolangContext context) {
		return switch (definition.lifetime()) {
			case KashiParticleDefinition.EmitterLifetime.Once once ->
					eval(compiler, context, once.activeTime());
			case KashiParticleDefinition.EmitterLifetime.Looping looping ->
					eval(compiler, context, looping.activeTime());
			case KashiParticleDefinition.EmitterLifetime.Expression expression -> 0;
		};
	}

	/** The alpha the particle would be drawn with right now, gradient or flat colour. */
	public static double alphaAt(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context) {
		KashiParticleDefinition.Tinting tinting = definition.tinting();

		if (tinting == null)
			return 1;

		if (tinting.color() != null)
			return eval(compiler, context, tinting.color().a());

		double t = tinting.interpolant() == null ? 0 : eval(compiler, context, tinting.interpolant());
		List<KashiParticleDefinition.GradientStop> stops = tinting.gradient();

		if (stops.isEmpty())
			return 1;

		if (t <= stops.get(0).position())
			return stops.get(0).a();

		for (int i = 1; i < stops.size(); i++) {
			if (t <= stops.get(i).position()) {
				KashiParticleDefinition.GradientStop lo = stops.get(i - 1);
				KashiParticleDefinition.GradientStop hi = stops.get(i);
				double span = hi.position() - lo.position();
				double f = span <= 0 ? 0 : (t - lo.position()) / span;

				return lo.a() + (hi.a() - lo.a()) * f;
			}
		}

		return stops.get(stops.size() - 1).a();
	}

	private static double eval(MolangCompiler compiler, MolangContext context, MolangExpr expr) {
		return expr.compile(compiler).eval(context);
	}
}
