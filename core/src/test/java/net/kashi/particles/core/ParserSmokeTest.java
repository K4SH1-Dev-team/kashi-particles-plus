package net.kashi.particles.core;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Standalone check that {@link KashiParticleDefinition} reads the reference Snowstorm export
 * faithfully, plus the failure cases the import wizard has to report clearly.
 *
 * <p>Deliberately dependency-free (no JUnit) so it runs against nothing but the bundled JDK
 * and gson — the same two things available inside MCreator and inside the generated mod.
 *
 * <p>Run via {@code tools/run-core-tests.ps1}.
 */
public final class ParserSmokeTest {

	private static final List<String> FAILURES = new ArrayList<>();
	private static int checks;

	public static void main(String[] args) throws IOException {
		Path fixture = Path.of(args.length > 0 ? args[0] : "core/src/test/resources/wind_3_1_p.particle.json");

		referenceEffect(parse(fixture));
		hexColoursAreArgbNotRgba();
		vanillaDescriptionIsRejectedClearly();
		truncatedEffectIsRejected();
		flipbookThatNeverAdvancesIsReportedNotRejected();
		unknownFacingFallsBackInsteadOfRejecting();
		materialsMapToBlendModes();
		unimplementedComponentsAreReportedNotFatal();
		initializationComponentsAreParsed();
		parametricMotionAndLightingAreParsed();
		curvesAreParsed();
		curvesAreSampledLikeWintersky();
		localSpaceIsParsed();
		eventsAreParsed();
		eventTypoIsReported();
		heavyEffectIsFlagged();

		System.out.println();

		if (FAILURES.isEmpty()) {
			System.out.println("OK - " + checks + " checks passed");

			return;
		}

		System.out.println("FAILED - " + FAILURES.size() + " of " + checks + " checks:");
		FAILURES.forEach(failure -> System.out.println("  - " + failure));
		System.exit(1);
	}

	// ------------------------------------------------------------- the cases

	private static void referenceEffect(KashiParticleDefinition definition) {
		System.out.println("reference effect: " + definition.identifier());

		eq("identifier", "dsl:wind_3_1_p", definition.identifier());
		eq("texture", "textures/particle/slash", definition.render().texture());
		eq("material", "particles_add", definition.render().material());
		eq("blend mode", KashiParticleDefinition.BlendMode.ADD, definition.render().blend());

		KashiParticleDefinition.EmitterRate.Steady rate =
				(KashiParticleDefinition.EmitterRate.Steady) definition.rate();
		eq("spawn_rate", 600.0, rate.spawnRate().constantValue());
		eq("max_particles", 1000.0, rate.maxParticles().constantValue());

		KashiParticleDefinition.EmitterLifetime.Once lifetime =
				(KashiParticleDefinition.EmitterLifetime.Once) definition.lifetime();
		eq("active_time", 1.2, lifetime.activeTime().constantValue());

		KashiParticleDefinition.EmitterShape.Sphere shape =
				(KashiParticleDefinition.EmitterShape.Sphere) definition.shape();
		eq("radius is an expression", false, shape.radius().isConstant());
		eq("radius source", "0.5+variable.emitter_age", shape.radius().source());
		eq("offset.x kept verbatim",
				"math.cos(230+variable.emitter_age*800)*(1.5+variable.emitter_age*4)",
				shape.offset().x().source());
		eq("direction", KashiParticleDefinition.EmitterDirection.Mode.OUTWARDS,
				((KashiParticleDefinition.EmitterDirection.Relative) shape.direction()).mode());

		eq("max_lifetime source", "variable.particle_random_3 * 0.5",
				definition.particleLifetime().maxLifetime().source());

		eq("initial spin rotation", "math.random(0,360)", definition.initialSpin().rotation().source());
		eq("initial spin rate", 10.0, definition.initialSpin().rotationRate().constantValue());

		// A bare number is a speed along the emitter's direction, not a velocity: the two forms of
		// initial_speed must stay distinguishable or the array form silently loses its axes.
		eq("initial speed rides the direction", true,
				definition.initialSpeed() instanceof KashiParticleDefinition.InitialSpeed.AlongDirection);
		eq("initial speed", 3.0, ((KashiParticleDefinition.InitialSpeed.AlongDirection)
				definition.initialSpeed()).speed().constantValue());

		KashiParticleDefinition withVelocity = definition(TINTED.replace(
				"\"minecraft:particle_lifetime_expression\"",
				"\"minecraft:particle_initial_speed\": [1, 2, 3],\n\"minecraft:particle_lifetime_expression\""));

		eq("an array is a velocity, not a speed", true,
				withVelocity.initialSpeed() instanceof KashiParticleDefinition.InitialSpeed.Velocity);
		eq("velocity keeps its z", 3.0, ((KashiParticleDefinition.InitialSpeed.Velocity)
				withVelocity.initialSpeed()).velocity().z().constantValue());

		// An empty particle_motion_dynamic still has to produce a component with zeroed defaults.
		eq("motion present", true, definition.motion() != null);
		eq("linear drag defaults to 0", 0.0, definition.motion().linearDrag().constantValue());

		KashiParticleDefinition.Appearance appearance = definition.appearance();
		eq("facing mode", KashiParticleDefinition.FacingMode.LOOKAT_XYZ, appearance.facing());
		eq("texture_width", 420.0, appearance.uv().textureWidth());
		eq("texture_height", 60.0, appearance.uv().textureHeight());
		eq("uv is animated", true, appearance.uv().isAnimated());

		KashiParticleDefinition.Flipbook flipbook = appearance.uv().flipbook();
		eq("size_UV x", 60.0, flipbook.sizeUv().x().constantValue());
		eq("step_UV x", 60.0, flipbook.stepUv().x().constantValue());
		eq("step_UV y", 0.0, flipbook.stepUv().y().constantValue());
		eq("max_frame", 7.0, flipbook.maxFrame());
		eq("stretch_to_lifetime", true, flipbook.stretchToLifetime());
		eq("loop", true, flipbook.loop());

		KashiParticleDefinition.Tinting tinting = definition.tinting();
		eq("interpolant kept with v. alias", "v.particle_age / v.particle_lifetime",
				tinting.interpolant().source());
		eq("gradient stops", 2, tinting.gradient().size());
		eq("first stop position", 0.0, tinting.gradient().get(0).position());
		eq("last stop position", 1.0, tinting.gradient().get(1).position());

		eq("nothing unsupported", List.of(), definition.unsupported());
	}

	/**
	 * Hex is alpha-first (#AARRGGBB), the Snowstorm convention. Ground truth: the reference
	 * effect's {@code "#FF00FF72"} renders green in Snowstorm, which only alpha-first produces.
	 */
	private static void hexColoursAreArgbNotRgba() {
		KashiParticleDefinition.GradientStop start = definition(TINTED).tinting().gradient().get(0);
		KashiParticleDefinition.GradientStop end = definition(TINTED).tinting().gradient().get(1);

		// #FF00FF72 = A:FF R:00 G:FF B:72 -> opaque green, the colour Snowstorm shows.
		eq("#FF00FF72 red", 0.0f, start.r());
		eq("#FF00FF72 green", 1.0f, start.g());
		eq("#FF00FF72 blue", 0x72 / 255.0f, start.b());
		eq("#FF00FF72 alpha", 1.0f, start.a());

		// #0000FF72 = A:00 -> fully transparent, i.e. the particle has faded out by end of life.
		eq("#0000FF72 green", 1.0f, end.g());
		eq("#0000FF72 fades out", 0.0f, end.a());
	}

	private static void vanillaDescriptionIsRejectedClearly() {
		rejects("vanilla Java particle description",
				"{\"textures\": [\"minecraft:generic_0\"]}",
				"vanilla Java particle description");
	}

	private static void truncatedEffectIsRejected() {
		rejects("effect with no shape", """
				{"format_version": "1.10.0", "particle_effect": {
					"description": {"identifier": "a:b", "basic_render_parameters":
						{"material": "particles_alpha", "texture": "t"}},
					"components": {}}}
				""", "no 'minecraft:emitter_shape_*'");
	}

	/**
	 * A flipbook with neither a frame rate nor stretch_to_lifetime is a still image, which is a
	 * thing an author may well have meant. It is reported, not refused.
	 */
	private static void flipbookThatNeverAdvancesIsReportedNotRejected() {
		KashiParticleDefinition definition = definition(TINTED.replace("""
				"stretch_to_lifetime": true""", """
				"stretch_to_lifetime": false"""));

		eq("still flipbook still imports", true, definition.appearance().uv().isAnimated());
		eq("still flipbook is reported", true, definition.unsupported().stream()
				.anyMatch(entry -> entry.component().contains("frames_per_second")));
	}

	/**
	 * A facing mode this parser does not know costs one field, not the whole effect: everything
	 * else in the file is still worth having.
	 */
	private static void unknownFacingFallsBackInsteadOfRejecting() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"size\": [1, 1],",
				"\"size\": [1, 1], \"facing_camera_mode\": \"lookat_sideways\","));

		eq("unknown facing still imports", KashiParticleDefinition.FacingMode.ROTATE_XYZ,
				definition.appearance().facing());
		eq("unknown facing is reported", true, definition.unsupported().stream()
				.anyMatch(entry -> entry.component().contains("lookat_sideways")));
	}

	/** Material names are matched exactly before any substring guessing. */
	private static void materialsMapToBlendModes() {
		eq("particles_add", KashiParticleDefinition.BlendMode.ADD, blendOf("particles_add"));
		eq("particles_blend", KashiParticleDefinition.BlendMode.ALPHA, blendOf("particles_blend"));
		// particles_alpha is an alpha test, not a blend - the same texture reads soft under one and
		// crisp under the other.
		eq("particles_alpha", KashiParticleDefinition.BlendMode.CUTOUT, blendOf("particles_alpha"));
		eq("particles_opaque", KashiParticleDefinition.BlendMode.OPAQUE, blendOf("particles_opaque"));

		// The case exact matching exists for: a custom name that substring matching would misread.
		eq("a custom name is not guessed by substring", KashiParticleDefinition.BlendMode.ALPHA,
				blendOf("shadow_blend"));
	}

	private static KashiParticleDefinition.BlendMode blendOf(String material) {
		return definition(TINTED.replace("particles_add", material)).render().blend();
	}

	/**
	 * An effect using components Snowstorm can export but we do not implement must still import,
	 * with a warning that names what will be lost — refusing it outright would be worse.
	 */
	private static void unimplementedComponentsAreReportedNotFatal() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"minecraft:emitter_shape_point\": {},",
				"""
				"minecraft:emitter_shape_point": {},
				"minecraft:particle_motion_collision": {"collision_drag": 1},
				"minecraft:particle_kill_plane": [0, 1, 0, 0],
				"minecraft:particle_wobble_nonsense": {},
				"""));

		// Only the invented one is left over: every component Snowstorm can export is now handled.
		eq("unsupported count", 1, definition.unsupported().size());

		KashiParticleDefinition.Unsupported nonsense = definition.unsupported().stream()
				.filter(u -> u.component().equals("minecraft:particle_wobble_nonsense"))
				.findFirst().orElseThrow();
		eq("invented component is not 'known'", false, nonsense.known());

		eq("collision is parsed", 1.0, definition.collision().drag());
		eq("kill plane is parsed", 1.0, definition.killPlane().b());

		// A radius of zero would never touch anything, so it takes Bedrock's floor instead.
		eq("collision radius has a floor", 0.01, definition.collision().radius());
	}

	/**
	 * The two initialization components carry the MoLang an effect uses to declare its own
	 * variables. They must parse into expressions, not land in the "unsupported" bucket.
	 */
	private static void initializationComponentsAreParsed() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"minecraft:emitter_shape_point\": {},",
				"""
				"minecraft:emitter_shape_point": {},
				"minecraft:emitter_initialization": {
					"creation_expression": "variable.spin = math.random(0,360);",
					"per_update_expression": "variable.spin = variable.spin + 1;"
				},
				"minecraft:particle_initialization": {
					"per_update_expression": "variable.fade = v.particle_age * 2;"
				},
				"""));

		eq("emitter_initialization parsed", true, definition.emitterInit() != null);
		eq("creation expression kept", "variable.spin = math.random(0,360);",
				definition.emitterInit().creation().source());
		eq("emitter per_update kept", "variable.spin = variable.spin + 1;",
				definition.emitterInit().perUpdate().source());

		eq("particle_initialization parsed", true, definition.particleInit() != null);
		eq("particle per_update kept", "variable.fade = v.particle_age * 2;",
				definition.particleInit().perUpdate().source());
		// A field the author left out is a no-op, not a failure.
		eq("missing per_render defaults to 0", true, definition.particleInit().perRender().isConstant());

		eq("initialization no longer counts as unsupported", 0, definition.unsupported().size());
	}

	/**
	 * Parametric motion replaces physics with a stated position, and the lighting component is an
	 * empty marker whose presence alone flips the particle from emissive to world-lit.
	 */
	private static void parametricMotionAndLightingAreParsed() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"minecraft:emitter_shape_point\": {},",
				"""
				"minecraft:emitter_shape_point": {},
				"minecraft:particle_motion_parametric": {
					"relative_position": ["v.particle_age * 2", 1, 0],
					"rotation": "v.particle_age * 90"
				},
				"minecraft:particle_appearance_lighting": {},
				"""));

		eq("parametric motion parsed", true, definition.motionParametric() != null);
		eq("relative_position kept", "v.particle_age * 2",
				definition.motionParametric().relativePosition().x().source());
		eq("parametric rotation kept", "v.particle_age * 90",
				definition.motionParametric().rotation().source());

		eq("lighting component flips the flag", true, definition.litByWorld());
		eq("neither counts as unsupported", 0, definition.unsupported().size());

		// Without the component the particle stays emissive, which is the Bedrock default.
		eq("default is emissive", false, definition(TINTED).litByWorld());
	}

	/**
	 * Curves sit beside {@code components}, not inside it, so they would never reach the component
	 * loop — a whole tab of the Snowstorm UI hangs off this one path.
	 */
	private static void curvesAreParsed() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"components\": {",
				"""
				"curves": {
					"variable.scaling": {
						"type": "linear",
						"input": "v.particle_age",
						"horizontal_range": "v.particle_lifetime",
						"nodes": [0.38, 0.16, 0, 0]
					}
				},
				"components": {"""));

		eq("curve parsed", 1, definition.curves().size());

		KashiParticleDefinition.Curve curve = definition.curves().get(0);

		eq("curve names its variable", "variable.scaling", curve.variable());
		eq("curve type", CurveSampler.Type.LINEAR, curve.type());
		eq("curve input kept", "v.particle_age", curve.input().source());
		eq("curve range kept", "v.particle_lifetime", curve.horizontalRange().source());
		eq("curve node count", 4, curve.nodes().length);

		// A file with no curves must still give an empty list rather than null.
		eq("no curves is empty, not null", 0, definition(TINTED).curves().size());
	}

	/**
	 * The index maths, checked against the behaviour of Wintersky's {@code calculateCurve}.
	 *
	 * <p>The catmull_rom case is the one worth pinning down: its first and last nodes are tangent
	 * handles rather than points on the curve, so a naive reading that samples all n nodes returns
	 * plausible-looking numbers that are wrong everywhere.
	 */
	private static void curvesAreSampledLikeWintersky() {
		double[] linear = {0, 10, 20};

		near("linear at 0", 0, CurveSampler.sample(CurveSampler.Type.LINEAR, 0, linear));
		near("linear at 0.25", 5, CurveSampler.sample(CurveSampler.Type.LINEAR, 0.25, linear));
		near("linear at 1", 20, CurveSampler.sample(CurveSampler.Type.LINEAR, 1, linear));
		near("linear clamps past the end", 20,
				CurveSampler.sample(CurveSampler.Type.LINEAR, 4, linear));

		// Handles 0 and 3; the visible curve runs from node 1 (=5) to node 2 (=9).
		double[] spline = {0, 5, 9, 100};

		near("catmull_rom starts at the second node", 5,
				CurveSampler.sample(CurveSampler.Type.CATMULL_ROM, 0, spline));
		near("catmull_rom ends at the second to last node", 9,
				CurveSampler.sample(CurveSampler.Type.CATMULL_ROM, 1, spline));

		// A four-node bezier is the plain cubic, so the midpoint has the closed form 1/8, 3/8, 3/8, 1/8.
		near("bezier midpoint", 0.5,
				CurveSampler.sample(CurveSampler.Type.BEZIER, 0.5, new double[] {0, 0, 1, 1}));

		// A single node is a constant, and no nodes at all must not divide or index into nothing.
		near("one node is constant", 7,
				CurveSampler.sample(CurveSampler.Type.LINEAR, 0.5, new double[] {7}));
		near("no nodes is zero", 0,
				CurveSampler.sample(CurveSampler.Type.LINEAR, 0.5, new double[0]));
	}

	/** The three switches of {@code minecraft:emitter_local_space} are independent. */
	private static void localSpaceIsParsed() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"minecraft:emitter_shape_point\": {},",
				"""
				"minecraft:emitter_shape_point": {},
				"minecraft:emitter_local_space": {"position": true, "velocity": true},
				"""));

		eq("local position", true, definition.localSpace().position());
		eq("local rotation defaults off", false, definition.localSpace().rotation());
		eq("local velocity", true, definition.localSpace().velocity());
		eq("local space no longer counts as unsupported", 0, definition.unsupported().size());

		// An effect that says nothing is world-space, and must not report null here.
		eq("absent means world space", false, definition(TINTED).localSpace().any());
	}

	/** Events, the way the real pack writes them, plus the node kinds it does not happen to use. */
	private static void eventsAreParsed() {
		KashiParticleDefinition definition = definition(TINTED
				.replace("\"components\": {", """
						"events": {
							"chain": {"particle_effect": {"effect": "akaza:compass5", "type": "emitter"}},
							"either": {"randomize": [
								{"weight": 3, "expression": "variable.a = 1;"},
								{"weight": 1, "sound_effect": {"event_name": "mob.blaze.shoot"}}]}
						},
						"components": {""")
				.replace("\"minecraft:emitter_shape_point\": {},", """
						"minecraft:emitter_shape_point": {},
						"minecraft:emitter_lifetime_events": {
							"creation_event": "chain",
							"expiration_event": ["chain", "either"],
							"timeline": {"0.5": "either", "0.1": "chain"}
						},
						"""));

		eq("events parsed", 2, definition.events().size());
		eq("creation trigger", List.of("chain"), definition.emitterEvents().creation());
		eq("a trigger may name several events", 2, definition.emitterEvents().expiration().size());

		// The timeline is written out of order in the JSON above on purpose: firing order depends
		// on it being sorted, and JSON object order is not guaranteed.
		eq("timeline is sorted by time", 0.1, definition.emitterEvents().timeline().get(0).at());

		eq("a particle_effect node", true,
				definition.events().get("chain") instanceof KashiParticleDefinition.EventNode.Effect);
		eq("it names the other effect", "akaza:compass5",
				((KashiParticleDefinition.EventNode.Effect) definition.events().get("chain")).effect());

		KashiParticleDefinition.EventNode.Randomize either =
				(KashiParticleDefinition.EventNode.Randomize) definition.events().get("either");

		eq("randomize keeps its options", 2, either.options().size());
		eq("randomize keeps its weights", 3.0, either.options().get(0).weight());

		// A sound is parsed and reported rather than dropped: it will simply never play.
		eq("sound is flagged", true, definition.unsupported().stream()
				.anyMatch(entry -> entry.component().contains("mob.blaze.shoot")));
	}

	/** A trigger naming an event that does not exist is a silent no-op; it has to be said. */
	private static void eventTypoIsReported() {
		KashiParticleDefinition definition = definition(TINTED.replace(
				"\"minecraft:emitter_shape_point\": {},",
				"""
				"minecraft:emitter_shape_point": {},
				"minecraft:emitter_lifetime_events": {"creation_event": "nonexistent"},
				"""));

		eq("missing event is reported", true, definition.unsupported().stream()
				.anyMatch(entry -> entry.component().equals("event: nonexistent")));
	}

	/** An effect that will genuinely spawn thousands of particles gets a heads-up, not silence. */
	private static void heavyEffectIsFlagged() {
		KashiParticleDefinition heavy = definition(TINTED.replace(
				"\"minecraft:emitter_shape_point\": {},",
				"""
				"minecraft:emitter_shape_point": {},
				"minecraft:emitter_rate_steady": {"spawn_rate": 500, "max_particles": 5000},
				"minecraft:emitter_lifetime_once": {"active_time": 5},
				"""));

		List<ParticleDiagnostics.Diagnostic> found = ParticleDiagnostics.analyse(heavy);

		eq("heavy effect is flagged", true, found.stream()
				.anyMatch(d -> d.code().equals("particle-volume-heavy")));

		// The stock fixture (1/s, default 10s active time = 10 particles) must stay quiet - the
		// point is catching the outliers, not adding noise to every ordinary effect.
		List<ParticleDiagnostics.Diagnostic> ordinary = ParticleDiagnostics.analyse(definition(TINTED));

		eq("an ordinary effect is not flagged", false, ordinary.stream()
				.anyMatch(d -> d.code().equals("particle-volume-heavy")));
	}

	// ---------------------------------------------------------------- harness

	/** A minimal but complete effect, used for the colour and flipbook cases. */
	private static final String TINTED = """
			{"format_version": "1.10.0", "particle_effect": {
				"description": {"identifier": "a:b", "basic_render_parameters":
					{"material": "particles_add", "texture": "t"}},
				"components": {
					"minecraft:emitter_shape_point": {},
					"minecraft:particle_lifetime_expression": {"max_lifetime": 1},
					"minecraft:particle_appearance_billboard": {
						"size": [1, 1],
						"uv": {"texture_width": 60, "texture_height": 60,
							"flipbook": {"base_UV": [0, 0], "size_UV": [60, 60],
								"step_UV": [60, 0], "max_frame": 7,
								"stretch_to_lifetime": true, "loop": true}}},
					"minecraft:particle_appearance_tinting": {"color": {
						"interpolant": "v.particle_age",
						"gradient": {"0.0": "#FF00FF72", "1.0": "#0000FF72"}}}}}}
			""";

	private static KashiParticleDefinition parse(Path path) throws IOException {
		return definition(Files.readString(path));
	}

	private static KashiParticleDefinition definition(String json) {
		return KashiParticleDefinition.parse(JsonParser.parseString(json).getAsJsonObject());
	}

	private static void rejects(String what, String json, String expectedFragment) {
		checks++;

		try {
			definition(json);
			FAILURES.add(what + ": expected a parse failure, but it was accepted");
		} catch (KashiParticleParseException expected) {
			if (expected.getMessage().contains(expectedFragment)) {
				System.out.println("  ok   rejects " + what);
			} else {
				FAILURES.add(what + ": message did not mention '" + expectedFragment
						+ "', was: " + expected.getMessage());
			}
		}
	}

	private static void near(String what, double expected, double actual) {
		checks++;

		if (Math.abs(expected - actual) < 1.0e-6) {
			System.out.println("  ok   " + what + " = " + actual);
		} else {
			FAILURES.add(what + ": expected " + expected + ", got " + actual);
		}
	}

	private static void eq(String what, Object expected, Object actual) {
		checks++;

		if (expected.equals(actual)) {
			System.out.println("  ok   " + what + " = " + actual);
		} else {
			FAILURES.add(what + ": expected " + expected + ", got " + actual);
		}
	}
}
