package net.kashi.particles.core;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * A parsed Bedrock/Snowstorm {@code .particle.json} effect.
 *
 * <p>This is the whole effect as data: every MoLang expression is kept as a {@link MolangExpr}
 * holding its raw source, so parsing stays free of any evaluation concern. Milestone 2 compiles
 * those expressions; milestone 3+ renders them.
 *
 * <p>Components the parser does not understand are not fatal — they are collected into
 * {@link #unsupported()} so the import wizard can warn that fidelity will be incomplete,
 * rather than rejecting an effect outright over one exotic component.
 */
public record KashiParticleDefinition(
		String identifier,
		Render render,
		EmitterRate rate,
		EmitterLifetime lifetime,
		EmitterShape shape,
		ParticleLifetime particleLifetime,
		InitialSpin initialSpin,
		InitialSpeed initialSpeed,
		MotionDynamic motion,
		Appearance appearance,
		Tinting tinting,
		EmitterInitialization emitterInit,
		ParticleInitialization particleInit,
		MotionParametric motionParametric,
		boolean litByWorld,
		LocalSpace localSpace,
		List<Curve> curves,
		Map<String, EventNode> events,
		LifetimeEvents emitterEvents,
		LifetimeEvents particleEvents,
		Collision collision,
		KillPlane killPlane,
		BlockFilter blockFilter,
		List<Unsupported> unsupported) {

	/**
	 * {@code minecraft:particle_motion_collision} — Snowstorm's "Collide" checkbox and its settings.
	 *
	 * @param drag         speed lost on contact, as a fraction per second of contact
	 * @param restitution  how much of the incoming speed bounces back; 0 means it stops dead
	 * @param radius       the sphere used against the world, in blocks
	 * @param expireOnContact whether the first contact kills the particle instead of bouncing it
	 */
	public record Collision(MolangExpr enabled, double drag, double restitution, double radius,
			boolean expireOnContact, List<String> events) {}

	/**
	 * {@code minecraft:particle_kill_plane} — a plane {@code ax + by + cz + d = 0}, in emitter
	 * space, that kills any particle crossing to its negative side.
	 */
	public record KillPlane(double a, double b, double c, double d) {}

	/**
	 * {@code minecraft:particle_expire_if_in_blocks} and {@code ..._if_not_in_blocks}.
	 *
	 * <p>The two are opposites and an effect may carry either or both, so they share one record:
	 * a particle dies inside anything in {@link #expireInside}, and outside everything in
	 * {@link #expireOutside}.
	 */
	public record BlockFilter(List<String> expireInside, List<String> expireOutside) {

		public static final BlockFilter NONE = new BlockFilter(List.of(), List.of());

		public boolean any() {
			return !this.expireInside.isEmpty() || !this.expireOutside.isEmpty();
		}
	}

	/**
	 * One entry of {@code particle_effect.events} — a named thing an effect can make happen.
	 *
	 * <p>An event is a tree, not a single action: {@link Sequence} runs its children in order and
	 * {@link Randomize} picks one by weight, and either may hold more of the same.
	 */
	public sealed interface EventNode {

		/** Spawns another effect. {@link #effect} is the other effect's Bedrock identifier. */
		record Effect(String effect, EffectType type, MolangExpr preEffectExpression)
				implements EventNode {}

		/** {@code sound_effect} — names a Bedrock sound event, which has no Java equivalent. */
		record Sound(String eventName) implements EventNode {}

		/** {@code expression} — MoLang run for its side effects, i.e. to set a variable. */
		record Expression(MolangExpr expression) implements EventNode {}

		record Sequence(List<EventNode> nodes) implements EventNode {}

		record Randomize(List<WeightedOption> options) implements EventNode {}

		/** {@code log} — a debug print in Bedrock. Kept so it round-trips, never acted on. */
		record Log(String message) implements EventNode {}
	}

	public record WeightedOption(double weight, EventNode node) {}

	/**
	 * Where a spawned effect is placed and whether it is tied to what spawned it.
	 *
	 * <p>{@code EMITTER_BOUND} differs from {@code EMITTER} only in that the new effect follows its
	 * parent instead of being left behind at the position it was born at.
	 */
	public enum EffectType { EMITTER, EMITTER_BOUND, PARTICLE, PARTICLE_WITH_VELOCITY }

	/**
	 * {@code minecraft:emitter_lifetime_events} and {@code minecraft:particle_lifetime_events} —
	 * which named events fire, and when.
	 *
	 * <p>Every field holds event names rather than nodes: Bedrock lets one event be triggered from
	 * several places, and resolving the name at trigger time is what makes that work.
	 */
	public record LifetimeEvents(List<String> creation, List<String> expiration,
			List<TimedEvents> timeline, List<TimedEvents> travelDistance,
			double travelDistanceLoopingStep, List<String> travelDistanceLooping) {

		public static final LifetimeEvents NONE = new LifetimeEvents(List.of(), List.of(), List.of(),
				List.of(), 0, List.of());

		public boolean any() {
			return !this.creation.isEmpty() || !this.expiration.isEmpty() || !this.timeline.isEmpty()
					|| !this.travelDistance.isEmpty() || !this.travelDistanceLooping.isEmpty();
		}
	}

	/** Event names that fire once the emitter passes {@link #at} — seconds, or blocks travelled. */
	public record TimedEvents(double at, List<String> events) {}

	/**
	 * The Bedrock identifiers of other effects this one starts through its events.
	 *
	 * <p>Importing an effect is not enough to make it play if it is only half of a chain: an effect
	 * naming {@code akaza:compass5} needs that one imported too, and nothing about the file itself
	 * says so. This is what lets the import wizard say it out loud.
	 */
	public List<String> referencedEffects() {
		List<String> referenced = new ArrayList<>();

		collectEffects(this.events.values(), referenced);

		return Collections.unmodifiableList(referenced);
	}

	private static void collectEffects(java.util.Collection<EventNode> nodes, List<String> into) {
		for (EventNode node : nodes) {
			switch (node) {
				case EventNode.Effect effect -> {
					if (!into.contains(effect.effect()))
						into.add(effect.effect());
				}
				case EventNode.Sequence sequence -> collectEffects(sequence.nodes(), into);
				case EventNode.Randomize randomize -> collectEffects(
						randomize.options().stream().map(WeightedOption::node).toList(), into);
				default -> { }
			}
		}
	}

	/**
	 * {@code minecraft:emitter_local_space} — Snowstorm's "Space" panel.
	 *
	 * <p>Only meaningful while the emitter is moving, which for an imported effect means one fired
	 * from an entity: with {@link #position} the whole effect travels with that entity instead of
	 * staying where it was fired, with {@link #rotation} it turns with it, and with
	 * {@link #velocity} particles are born already carrying the entity's motion.
	 *
	 * <p>An effect that declares none of them is world-space, and a spawn that names no entity has
	 * nothing to be local to — in both cases this component changes nothing.
	 */
	public record LocalSpace(boolean position, boolean rotation, boolean velocity) {

		public static final LocalSpace NONE = new LocalSpace(false, false, false);

		public boolean any() {
			return this.position || this.rotation || this.velocity;
		}
	}

	/**
	 * One entry of {@code particle_effect.curves} — Snowstorm's "Variables &amp; Curves" tab.
	 *
	 * <p>A curve is an assignment, not a shape: it computes a value from {@link #input} and stores
	 * it in {@link #variable}, which the rest of the effect then reads like any other
	 * {@code variable.*}. Effects here routinely drive their size that way, so an unevaluated
	 * curve does not degrade an effect — it makes it invisible.
	 *
	 * <p>Exactly one of {@link #nodes} and {@link #chain} is non-null, according to {@link #type}.
	 */
	public record Curve(String variable, CurveSampler.Type type, MolangExpr input,
			MolangExpr horizontalRange, double[] nodes, CurveSampler.ChainKey[] chain) {}

	/**
	 * {@code minecraft:emitter_initialization} — where an effect sets up its own MoLang variables.
	 *
	 * <p>{@link #creation} runs once when the emitter starts, {@link #perUpdate} every emitter tick.
	 * Both are usually assignments ({@code variable.x = ...}); whatever they define is readable by
	 * the effect's other expressions and by its particles.
	 */
	public record EmitterInitialization(MolangExpr creation, MolangExpr perUpdate) {}

	/**
	 * {@code minecraft:particle_initialization} — per-particle MoLang setup.
	 *
	 * <p>{@link #perUpdate} runs on every particle tick, {@link #perRender} on every frame before
	 * the particle is drawn.
	 */
	public record ParticleInitialization(MolangExpr perUpdate, MolangExpr perRender) {}

	/**
	 * A component the parser read but does not act on.
	 *
	 * <p>{@code known} separates "Bedrock component we have not implemented yet", where
	 * {@code impact} says what the effect will lose, from "we have never heard of this",
	 * which usually means a typo or a newer format version.
	 */
	public record Unsupported(String component, String impact, boolean known) {}

	/**
	 * Components Snowstorm can export that this parser deliberately does not handle yet,
	 * mapped to what the imported effect loses by their absence.
	 *
	 * <p>Derived from Snowstorm's own {@code src/input_structure.js}, so the list tracks what
	 * a user can actually produce in the editor rather than the whole Bedrock specification.
	 */
	private static final Map<String, String> KNOWN_UNIMPLEMENTED = Map.of();

	// ---------------------------------------------------------------- render

	/**
	 * How the effect's texture is blended.
	 *
	 * <p>{@code CUTOUT} is Bedrock's {@code particles_alpha}: a hard alpha <em>test</em>, where a
	 * pixel is either drawn at full strength or not at all. It is a different thing from
	 * {@code ALPHA} ({@code particles_blend}), which fades smoothly, and an effect authored for one
	 * looks wrong under the other — soft edges where the author wanted crisp ones.
	 */
	public enum BlendMode { ALPHA, CUTOUT, ADD, OPAQUE }

	/** {@code description.basic_render_parameters}. */
	public record Render(String material, String texture, BlendMode blend) {}

	// --------------------------------------------------------------- emitter

	/** {@code minecraft:emitter_rate_*}. */
	public sealed interface EmitterRate {
		record Steady(MolangExpr spawnRate, MolangExpr maxParticles) implements EmitterRate {}
		record Instant(MolangExpr numParticles) implements EmitterRate {}
		record Manual(MolangExpr maxParticles) implements EmitterRate {}
	}

	/** {@code minecraft:emitter_lifetime_*}. */
	public sealed interface EmitterLifetime {
		record Once(MolangExpr activeTime) implements EmitterLifetime {}
		record Looping(MolangExpr activeTime, MolangExpr sleepTime) implements EmitterLifetime {}
		record Expression(MolangExpr activation, MolangExpr expiration) implements EmitterLifetime {}
	}

	/**
	 * Which way newly spawned particles are pushed.
	 *
	 * <p>{@code OUTWARDS}/{@code INWARDS} are relative to the shape's centre; a custom vector
	 * is taken as-is in emitter-local space.
	 */
	public sealed interface EmitterDirection {
		enum Mode { OUTWARDS, INWARDS }

		record Relative(Mode mode) implements EmitterDirection {}
		record Custom(Vec3Expr vector) implements EmitterDirection {}
	}

	/** {@code minecraft:emitter_shape_*}. All offsets are emitter-local. */
	public sealed interface EmitterShape {
		Vec3Expr offset();

		record Point(Vec3Expr offset, EmitterDirection direction) implements EmitterShape {}

		record Sphere(Vec3Expr offset, MolangExpr radius, boolean surfaceOnly,
				EmitterDirection direction) implements EmitterShape {}

		record Box(Vec3Expr offset, Vec3Expr halfDimensions, boolean surfaceOnly,
				EmitterDirection direction) implements EmitterShape {}

		record Disc(Vec3Expr offset, Vec3Expr planeNormal, MolangExpr radius, boolean surfaceOnly,
				EmitterDirection direction) implements EmitterShape {}

		record EntityAabb(Vec3Expr offset, boolean surfaceOnly,
				EmitterDirection direction) implements EmitterShape {}
	}

	// -------------------------------------------------------------- particle

	/** {@code minecraft:particle_lifetime_expression}. */
	public record ParticleLifetime(MolangExpr maxLifetime, MolangExpr expiration) {}

	/** {@code minecraft:particle_initial_spin}. */
	public record InitialSpin(MolangExpr rotation, MolangExpr rotationRate) {}

	/**
	 * {@code minecraft:particle_initial_speed}, in either of the two forms Bedrock accepts.
	 *
	 * <p>The distinction is not cosmetic. A bare number is a <b>speed</b> along whatever direction
	 * the emitter shape chose; a three-element array is an outright <b>velocity</b> that ignores
	 * that direction. Collapsing them loses the difference silently — the particle still moves, just
	 * not where the effect said — so the two are kept apart here and the runtime asks which it has.
	 */
	public sealed interface InitialSpeed {
		record AlongDirection(MolangExpr speed) implements InitialSpeed {}
		record Velocity(Vec3Expr velocity) implements InitialSpeed {}
	}

	/** {@code minecraft:particle_motion_dynamic}. */
	public record MotionDynamic(Vec3Expr linearAcceleration, MolangExpr linearDrag,
			MolangExpr rotationAcceleration, MolangExpr rotationDrag) {}

	/**
	 * {@code minecraft:particle_motion_parametric} — position driven by expression instead of physics.
	 *
	 * <p>Where dynamic motion integrates acceleration and drag, parametric motion simply states
	 * where the particle is, relative to its emitter, at any moment. When present it replaces the
	 * dynamic integration entirely rather than adding to it.
	 */
	public record MotionParametric(Vec3Expr relativePosition, Vec3Expr direction, MolangExpr rotation) {}

	/**
	 * How the billboard is oriented. Bedrock has three families here and they behave very
	 * differently, so mixing them up is what makes an effect look wrong or vanish:
	 *
	 * <ul>
	 * <li><b>rotate_* / lookat_*</b> — camera-facing billboards. Always visible.</li>
	 * <li><b>direction_* / lookat_direction</b> — oriented by the particle's own direction of
	 *     travel. A slash aligns with where it flies.</li>
	 * <li><b>emitter_transform_*</b> — a fixed plane pinned to the emitter's axes. Can be seen
	 *     edge-on and disappear; that is authored behaviour, not a fault.</li>
	 * </ul>
	 */
	public enum FacingMode {
		ROTATE_XYZ, ROTATE_Y, LOOKAT_XYZ, LOOKAT_Y, LOOKAT_DIRECTION,
		DIRECTION_X, DIRECTION_Y, DIRECTION_Z,
		EMITTER_TRANSFORM_XY, EMITTER_TRANSFORM_XZ, EMITTER_TRANSFORM_YZ
	}

	/**
	 * Flipbook animation over the texture sheet.
	 *
	 * <p>All UV values are in texture pixels, to be divided by the {@link Uv} sheet dimensions
	 * at render time — Bedrock authors them in pixels, not normalised coordinates.
	 */
	public record Flipbook(Vec2Expr baseUv, Vec2Expr sizeUv, Vec2Expr stepUv, MolangExpr fps,
			double maxFrame, boolean stretchToLifetime, boolean loop) {}

	/** {@code particle_appearance_billboard.uv} — either a static rect or a {@link Flipbook}. */
	public record Uv(double textureWidth, double textureHeight, Vec2Expr uv, Vec2Expr uvSize,
			Flipbook flipbook) {

		public boolean isAnimated() {
			return this.flipbook != null;
		}
	}

	/** {@code minecraft:particle_appearance_billboard}. */
	public record Appearance(Vec2Expr size, FacingMode facing, Uv uv) {}

	/** One stop of a {@code particle_appearance_tinting} gradient, RGBA in 0..1. */
	public record GradientStop(double position, float r, float g, float b, float a) {}

	/**
	 * {@code minecraft:particle_appearance_tinting}.
	 *
	 * <p>Either a gradient sampled by {@link #interpolant}, or a flat {@link #color} — exactly
	 * one of the two is non-null.
	 */
	public record Tinting(MolangExpr interpolant, List<GradientStop> gradient, ColorExpr color) {}

	/** A colour whose channels are themselves MoLang, as Bedrock allows. */
	public record ColorExpr(MolangExpr r, MolangExpr g, MolangExpr b, MolangExpr a) {}

	// ---------------------------------------------------------------- tuples

	public record Vec2Expr(MolangExpr x, MolangExpr y) {}

	public record Vec3Expr(MolangExpr x, MolangExpr y, MolangExpr z) {}

	// =============================================================== parsing

	private static final String FORMAT_KEY = "format_version";
	private static final String EFFECT_KEY = "particle_effect";

	/**
	 * Parses a full {@code .particle.json} document.
	 *
	 * @param root the top-level object, holding {@code format_version} and {@code particle_effect}
	 * @throws KashiParticleParseException if the document is not a Bedrock particle effect
	 */
	public static KashiParticleDefinition parse(JsonObject root) {
		if (!root.has(EFFECT_KEY)) {
			// The single most likely mistake: a vanilla Java particle description, which shares
			// the .json extension and nothing else.
			throw new KashiParticleParseException("", root.has("textures")
					? "this looks like a vanilla Java particle description, not a Bedrock "
							+ "particle effect — expected a '" + EFFECT_KEY + "' object"
					: "missing '" + EFFECT_KEY + "' — not a Bedrock particle effect");
		}

		if (!root.has(FORMAT_KEY))
			throw new KashiParticleParseException("", "missing '" + FORMAT_KEY + "'");

		JsonObject effect = obj(root, EFFECT_KEY, EFFECT_KEY);
		JsonObject description = obj(effect, "description", EFFECT_KEY + ".description");
		JsonObject components = obj(effect, "components", EFFECT_KEY + ".components");

		List<Unsupported> unsupported = new ArrayList<>();
		Builder builder = new Builder();

		for (Map.Entry<String, JsonElement> entry : components.entrySet()) {
			String component = entry.getKey();
			String path = EFFECT_KEY + ".components." + component;

			if (builder.accept(component, entry.getValue(), path))
				continue;

			String impact = KNOWN_UNIMPLEMENTED.get(component);

			unsupported.add(impact != null ? new Unsupported(component, impact, true)
					: new Unsupported(component, "unrecognised component - check the spelling "
							+ "and the effect's format_version", false));
		}

		String path = EFFECT_KEY + ".description";
		String identifier = string(description, "identifier", path + ".identifier");

		return builder.build(identifier, parseRenderParameters(description),
				curves(effect.getAsJsonObject("curves")),
				events(effect.getAsJsonObject("events")), unsupported);
	}

	/** {@code particle_effect.events}, which like {@code curves} sits outside {@code components}. */
	private static Map<String, EventNode> events(JsonObject owner) {
		if (owner == null)
			return Map.of();

		Map<String, EventNode> events = new java.util.LinkedHashMap<>();

		for (Map.Entry<String, JsonElement> entry : owner.entrySet()) {
			String path = EFFECT_KEY + ".events." + entry.getKey();

			events.put(entry.getKey(), eventNode(asObj(entry.getValue(), path), path));
		}

		return Collections.unmodifiableMap(events);
	}

	/**
	 * Reads one event node.
	 *
	 * <p>A node object may carry several kinds at once — Bedrock treats {@code sound_effect} beside
	 * {@code particle_effect} as "do both" — so anything with more than one becomes a sequence
	 * rather than the first one winning.
	 */
	private static EventNode eventNode(JsonObject owner, String path) {
		List<EventNode> parts = new ArrayList<>();

		if (owner.has("particle_effect")) {
			JsonObject spawn = obj(owner, "particle_effect", path + ".particle_effect");
			String typeName = spawn.has("type")
					? string(spawn, "type", path + ".particle_effect.type").trim().toUpperCase(Locale.ROOT)
					: "EMITTER";

			EffectType type;

			try {
				type = EffectType.valueOf(typeName);
			} catch (IllegalArgumentException unknown) {
				throw new KashiParticleParseException(path + ".particle_effect.type",
						"unknown effect type '" + typeName.toLowerCase(Locale.ROOT) + "'");
			}

			parts.add(new EventNode.Effect(
					string(spawn, "effect", path + ".particle_effect.effect"), type,
					molang(spawn, "pre_effect_expression", path + ".particle_effect.pre_effect_expression", 0)));
		}

		if (owner.has("sound_effect")) {
			JsonObject sound = obj(owner, "sound_effect", path + ".sound_effect");

			parts.add(new EventNode.Sound(string(sound, "event_name", path + ".sound_effect.event_name")));
		}

		if (owner.has("expression"))
			parts.add(new EventNode.Expression(molang(owner, "expression", path + ".expression", 0)));

		if (owner.has("log"))
			parts.add(new EventNode.Log(string(owner, "log", path + ".log")));

		if (owner.has("sequence")) {
			parts.add(new EventNode.Sequence(
					childNodes(owner.get("sequence"), path + ".sequence")));
		}

		if (owner.has("randomize")) {
			JsonElement element = owner.get("randomize");

			if (!element.isJsonArray())
				throw new KashiParticleParseException(path + ".randomize", "expected an array of options");

			List<WeightedOption> options = new ArrayList<>();
			JsonArray array = element.getAsJsonArray();

			for (int i = 0; i < array.size(); i++) {
				String optionPath = path + ".randomize[" + i + "]";
				JsonObject option = asObj(array.get(i), optionPath);

				options.add(new WeightedOption(number(option, "weight", optionPath + ".weight", 1),
						eventNode(option, optionPath)));
			}

			parts.add(new EventNode.Randomize(Collections.unmodifiableList(options)));
		}

		// An empty event is not a mistake worth refusing a file over - real packs leave them behind
		// after an author deletes what an event used to do, and it simply does nothing.
		if (parts.isEmpty())
			return new EventNode.Sequence(List.of());

		return parts.size() == 1 ? parts.get(0)
				: new EventNode.Sequence(Collections.unmodifiableList(parts));
	}

	private static List<EventNode> childNodes(JsonElement element, String path) {
		if (!element.isJsonArray())
			throw new KashiParticleParseException(path, "expected an array of event nodes");

		List<EventNode> nodes = new ArrayList<>();
		JsonArray array = element.getAsJsonArray();

		for (int i = 0; i < array.size(); i++)
			nodes.add(eventNode(asObj(array.get(i), path + "[" + i + "]"), path + "[" + i + "]"));

		return Collections.unmodifiableList(nodes);
	}

	private static LifetimeEvents lifetimeEvents(JsonObject owner, String path) {
		return new LifetimeEvents(
				eventNames(owner.get("creation_event"), path + ".creation_event"),
				eventNames(owner.get("expiration_event"), path + ".expiration_event"),
				timedEvents(owner.getAsJsonObject("timeline"), path + ".timeline"),
				timedEvents(owner.getAsJsonObject("travel_distance_events"),
						path + ".travel_distance_events"),
				number(owner, "distance", path + ".distance", 0),
				eventNames(owner.get("effects"), path + ".effects"));
	}

	/** An event trigger names either one event or a list of them; both are common in real packs. */
	private static List<String> eventNames(JsonElement element, String path) {
		if (element == null || element.isJsonNull())
			return List.of();

		if (element.isJsonArray()) {
			List<String> names = new ArrayList<>();

			element.getAsJsonArray().forEach(entry -> names.add(entry.getAsString()));

			return Collections.unmodifiableList(names);
		}

		return List.of(element.getAsString());
	}

	/** The block-name list of the {@code expire_if_*_in_blocks} components. */
	private static List<String> blockList(JsonElement element, String path) {
		if (!element.isJsonArray())
			throw new KashiParticleParseException(path, "expected an array of block names");

		List<String> blocks = new ArrayList<>();

		element.getAsJsonArray().forEach(entry -> blocks.add(entry.getAsString()));

		return Collections.unmodifiableList(blocks);
	}

	private static List<TimedEvents> timedEvents(JsonObject owner, String path) {
		if (owner == null)
			return List.of();

		List<TimedEvents> timeline = new ArrayList<>();

		for (Map.Entry<String, JsonElement> entry : owner.entrySet()) {
			double at;

			try {
				at = Double.parseDouble(entry.getKey());
			} catch (NumberFormatException notANumber) {
				throw new KashiParticleParseException(path,
						"'" + entry.getKey() + "' is not a time");
			}

			timeline.add(new TimedEvents(at,
					eventNames(entry.getValue(), path + "." + entry.getKey())));
		}

		// Firing in order matters: JSON object order is not guaranteed to be sorted.
		timeline.sort((a, b) -> Double.compare(a.at(), b.at()));

		return Collections.unmodifiableList(timeline);
	}

	/**
	 * Reads {@code particle_effect.curves}, which sits beside {@code components} rather than
	 * inside it — a curve is not a component and would never reach the component loop.
	 */
	private static List<Curve> curves(JsonObject owner) {
		if (owner == null)
			return List.of();

		List<Curve> curves = new ArrayList<>();

		for (Map.Entry<String, JsonElement> entry : owner.entrySet())
			curves.add(curve(entry.getKey(), asObj(entry.getValue(),
					EFFECT_KEY + ".curves." + entry.getKey()), EFFECT_KEY + ".curves." + entry.getKey()));

		return Collections.unmodifiableList(curves);
	}

	private static Curve curve(String variable, JsonObject owner, String path) {
		String typeName = owner.has("type")
				? string(owner, "type", path + ".type").trim().toLowerCase(Locale.ROOT)
				: "linear";

		CurveSampler.Type type = switch (typeName) {
			case "linear" -> CurveSampler.Type.LINEAR;
			case "catmull_rom" -> CurveSampler.Type.CATMULL_ROM;
			case "bezier" -> CurveSampler.Type.BEZIER;
			case "bezier_chain" -> CurveSampler.Type.BEZIER_CHAIN;
			default -> throw new KashiParticleParseException(path + ".type",
					"unknown curve type '" + typeName + "' - expected linear, catmull_rom, "
							+ "bezier or bezier_chain");
		};

		MolangExpr input = molang(owner, "input", path + ".input", 0);
		// A missing or zero range would divide by zero; Wintersky reads that as "always at 0".
		MolangExpr range = molang(owner, "horizontal_range", path + ".horizontal_range", 1);
		JsonElement nodes = owner.get("nodes");

		if (nodes == null || nodes.isJsonNull())
			throw new KashiParticleParseException(path, "missing 'nodes'");

		if (type == CurveSampler.Type.BEZIER_CHAIN)
			return new Curve(variable, type, input, range, null, chainKeys(nodes, path + ".nodes"));

		if (!nodes.isJsonArray())
			throw new KashiParticleParseException(path + ".nodes",
					"expected an array of numbers for a " + typeName + " curve");

		JsonArray array = nodes.getAsJsonArray();
		double[] values = new double[array.size()];

		for (int i = 0; i < values.length; i++)
			values[i] = array.get(i).getAsDouble();

		return new Curve(variable, type, input, range, values, null);
	}

	private static CurveSampler.ChainKey[] chainKeys(JsonElement element, String path) {
		if (!element.isJsonObject())
			throw new KashiParticleParseException(path,
					"a bezier_chain's nodes are an object keyed by time");

		List<CurveSampler.ChainKey> keys = new ArrayList<>();

		for (Map.Entry<String, JsonElement> entry : element.getAsJsonObject().entrySet()) {
			double time;

			try {
				time = Double.parseDouble(entry.getKey());
			} catch (NumberFormatException notANumber) {
				throw new KashiParticleParseException(path,
						"node key '" + entry.getKey() + "' is not a number");
			}

			JsonObject node = asObj(entry.getValue(), path + "." + entry.getKey());
			String nodePath = path + "." + entry.getKey();

			// A smooth key writes only "value"/"slope"; a corner splits them into left and right.
			double value = number(node, "value", nodePath + ".value", 0);
			double slope = number(node, "slope", nodePath + ".slope", 0);

			keys.add(new CurveSampler.ChainKey(time,
					number(node, "left_value", nodePath + ".left_value", value),
					number(node, "right_value", nodePath + ".right_value", value),
					number(node, "left_slope", nodePath + ".left_slope", slope),
					number(node, "right_slope", nodePath + ".right_slope", slope)));
		}

		keys.sort((a, b) -> Double.compare(a.time(), b.time()));

		return keys.toArray(new CurveSampler.ChainKey[0]);
	}

	private static Render parseRenderParameters(JsonObject description) {
		String path = EFFECT_KEY + ".description.basic_render_parameters";
		JsonObject params = obj(description, "basic_render_parameters", path);
		String material = string(params, "material", path + ".material");
		String texture = string(params, "texture", path + ".texture");

		return new Render(material, texture, blendOf(material));
	}

	/**
	 * Maps a Bedrock material name onto a blend mode.
	 *
	 * <p>The four Snowstorm materials are matched exactly first, because substring matching gets
	 * them wrong the moment a pack invents a name: a custom material called {@code shadow_blend}
	 * contains neither "add" nor "opaque" and would land on alpha by luck rather than by reading.
	 * Substrings remain as a last resort for names this does not know, where a plausible guess
	 * still beats refusing an effect that is otherwise fine.
	 */
	private static BlendMode blendOf(String material) {
		String name = material.trim().toLowerCase(Locale.ROOT);

		return switch (name) {
			case "particles_add", "particles_blend_add" -> BlendMode.ADD;
			case "particles_opaque" -> BlendMode.OPAQUE;
			case "particles_alpha" -> BlendMode.CUTOUT;
			case "particles_blend" -> BlendMode.ALPHA;
			default -> {
				if (name.contains("add"))
					yield BlendMode.ADD;

				yield name.contains("opaque") ? BlendMode.OPAQUE : BlendMode.ALPHA;
			}
		};
	}

	/** Accumulates components as they are read, then validates the set as a whole. */
	private static final class Builder {

		private EmitterRate rate;
		private EmitterLifetime lifetime;
		private EmitterShape shape;
		private ParticleLifetime particleLifetime;
		private InitialSpin initialSpin;
		private InitialSpeed initialSpeed;
		private MotionDynamic motion;
		private Appearance appearance;
		private Tinting tinting;
		private EmitterInitialization emitterInit;
		private ParticleInitialization particleInit;
		private MotionParametric motionParametric;
		private boolean litByWorld;
		private LocalSpace localSpace = LocalSpace.NONE;

		/**
		 * Fields the parser recovered from rather than rejecting the effect over.
		 *
		 * <p>Kept apart from the unrecognised-component list only until {@link #build}, which
		 * merges them: to a caller they are the same thing, "this imported but something in it is
		 * not being honoured".
		 */
		private final List<Unsupported> notes = new ArrayList<>();
		private LifetimeEvents emitterEvents = LifetimeEvents.NONE;
		private LifetimeEvents particleEvents = LifetimeEvents.NONE;
		private Collision collision;
		private KillPlane killPlane;
		private List<String> expireInside = List.of();
		private List<String> expireOutside = List.of();

		/** @return whether the component was recognised */
		boolean accept(String key, JsonElement value, String path) {
			switch (key) {
				case "minecraft:emitter_rate_steady" -> {
					JsonObject o = asObj(value, path);
					this.rate = new EmitterRate.Steady(molang(o, "spawn_rate", path + ".spawn_rate", 1),
							molang(o, "max_particles", path + ".max_particles", 50));
				}
				case "minecraft:emitter_rate_instant" -> {
					JsonObject o = asObj(value, path);
					this.rate = new EmitterRate.Instant(molang(o, "num_particles", path + ".num_particles", 10));
				}
				case "minecraft:emitter_rate_manual" -> {
					JsonObject o = asObj(value, path);
					this.rate = new EmitterRate.Manual(molang(o, "max_particles", path + ".max_particles", 50));
				}
				case "minecraft:emitter_lifetime_once" -> {
					JsonObject o = asObj(value, path);
					this.lifetime = new EmitterLifetime.Once(molang(o, "active_time", path + ".active_time", 10));
				}
				case "minecraft:emitter_lifetime_looping" -> {
					JsonObject o = asObj(value, path);
					this.lifetime = new EmitterLifetime.Looping(
							molang(o, "active_time", path + ".active_time", 10),
							molang(o, "sleep_time", path + ".sleep_time", 0));
				}
				case "minecraft:emitter_lifetime_expression" -> {
					JsonObject o = asObj(value, path);
					this.lifetime = new EmitterLifetime.Expression(
							molang(o, "activation_expression", path + ".activation_expression", 1),
							molang(o, "expiration_expression", path + ".expiration_expression", 0));
				}
				case "minecraft:emitter_shape_point" -> {
					JsonObject o = asObj(value, path);
					this.shape = new EmitterShape.Point(vec3(o, "offset", path + ".offset", 0),
							direction(o, path));
				}
				case "minecraft:emitter_shape_sphere" -> {
					JsonObject o = asObj(value, path);
					this.shape = new EmitterShape.Sphere(vec3(o, "offset", path + ".offset", 0),
							molang(o, "radius", path + ".radius", 1),
							bool(o, "surface_only", false), direction(o, path));
				}
				case "minecraft:emitter_shape_box" -> {
					JsonObject o = asObj(value, path);
					this.shape = new EmitterShape.Box(vec3(o, "offset", path + ".offset", 0),
							vec3(o, "half_dimensions", path + ".half_dimensions", 0.5),
							bool(o, "surface_only", false), direction(o, path));
				}
				case "minecraft:emitter_shape_disc" -> {
					JsonObject o = asObj(value, path);
					this.shape = new EmitterShape.Disc(vec3(o, "offset", path + ".offset", 0),
							planeNormal(o, path), molang(o, "radius", path + ".radius", 1),
							bool(o, "surface_only", false), direction(o, path));
				}
				case "minecraft:emitter_shape_entity_aabb" -> {
					JsonObject o = asObj(value, path);
					this.shape = new EmitterShape.EntityAabb(vec3(o, "offset", path + ".offset", 0),
							bool(o, "surface_only", false), direction(o, path));
				}
				case "minecraft:particle_lifetime_expression" -> {
					JsonObject o = asObj(value, path);
					this.particleLifetime = new ParticleLifetime(
							molang(o, "max_lifetime", path + ".max_lifetime", 1),
							molang(o, "expiration_expression", path + ".expiration_expression", 0));
				}
				case "minecraft:particle_initial_spin" -> {
					JsonObject o = asObj(value, path);
					this.initialSpin = new InitialSpin(molang(o, "rotation", path + ".rotation", 0),
							molang(o, "rotation_rate", path + ".rotation_rate", 0));
				}
				case "minecraft:particle_initial_speed" -> this.initialSpeed = initialSpeed(value, path);
				case "minecraft:particle_motion_dynamic" -> {
					JsonObject o = asObj(value, path);
					this.motion = new MotionDynamic(
							vec3(o, "linear_acceleration", path + ".linear_acceleration", 0),
							molang(o, "linear_drag_coefficient", path + ".linear_drag_coefficient", 0),
							molang(o, "rotation_acceleration", path + ".rotation_acceleration", 0),
							molang(o, "rotation_drag_coefficient", path + ".rotation_drag_coefficient", 0));
				}
				case "minecraft:particle_appearance_billboard" ->
					this.appearance = appearance(asObj(value, path), path, this.notes);
				case "minecraft:particle_appearance_tinting" -> this.tinting = tinting(asObj(value, path), path);
				case "minecraft:particle_motion_parametric" -> {
					JsonObject o = asObj(value, path);
					this.motionParametric = new MotionParametric(
							vec3(o, "relative_position", path + ".relative_position", 0),
							vec3(o, "direction", path + ".direction", 0),
							molang(o, "rotation", path + ".rotation", 0));
				}
				case "minecraft:particle_motion_collision" -> {
					JsonObject o = asObj(value, path);
					this.collision = new Collision(
							molang(o, "enabled", path + ".enabled", 1),
							number(o, "collision_drag", path + ".collision_drag", 0),
							number(o, "coefficient_of_restitution", path + ".coefficient_of_restitution", 0),
							// A zero radius would never touch anything; Bedrock's default is 0.01.
							Math.max(0.01, number(o, "collision_radius", path + ".collision_radius", 0.01)),
							bool(o, "expire_on_contact", false),
							eventNames(o.get("events"), path + ".events"));
				}
				case "minecraft:particle_kill_plane" -> {
					// The component's value is the array itself, not an object wrapping one.
					if (!value.isJsonArray() || value.getAsJsonArray().size() != 4)
						throw new KashiParticleParseException(path,
								"expected the four coefficients of a plane, [a, b, c, d]");

					JsonArray plane = value.getAsJsonArray();

					this.killPlane = new KillPlane(plane.get(0).getAsDouble(), plane.get(1).getAsDouble(),
							plane.get(2).getAsDouble(), plane.get(3).getAsDouble());
				}
				case "minecraft:particle_expire_if_in_blocks" ->
					this.expireInside = blockList(value, path);
				case "minecraft:particle_expire_if_not_in_blocks" ->
					this.expireOutside = blockList(value, path);
				case "minecraft:emitter_shape_custom" -> {
					// Bedrock's custom shape is a point placed by expression: it carries an offset
					// and a direction and nothing else, so a Point models it exactly.
					JsonObject o = asObj(value, path);
					this.shape = new EmitterShape.Point(vec3(o, "offset", path + ".offset", 0),
							direction(o, path));
				}
				case "minecraft:emitter_lifetime_events" ->
					this.emitterEvents = lifetimeEvents(asObj(value, path), path);
				case "minecraft:particle_lifetime_events" ->
					this.particleEvents = lifetimeEvents(asObj(value, path), path);
				case "minecraft:emitter_local_space" -> {
					JsonObject o = asObj(value, path);
					this.localSpace = new LocalSpace(bool(o, "position", false),
							bool(o, "rotation", false), bool(o, "velocity", false));
				}
				case "minecraft:particle_appearance_lighting" ->
					// An empty component; its mere presence means "respect world light".
					this.litByWorld = true;
				case "minecraft:emitter_initialization" -> {
					JsonObject o = asObj(value, path);
					// A missing expression is a no-op, not an error: Snowstorm writes only the
					// fields the author actually filled in.
					this.emitterInit = new EmitterInitialization(
							molang(o, "creation_expression", path + ".creation_expression", 0),
							molang(o, "per_update_expression", path + ".per_update_expression", 0));
				}
				case "minecraft:particle_initialization" -> {
					JsonObject o = asObj(value, path);
					this.particleInit = new ParticleInitialization(
							molang(o, "per_update_expression", path + ".per_update_expression", 0),
							molang(o, "per_render_expression", path + ".per_render_expression", 0));
				}
				default -> {
					return false;
				}
			}

			return true;
		}

		KashiParticleDefinition build(String identifier, Render render, List<Curve> curves,
				Map<String, EventNode> events, List<Unsupported> componentLevel) {
			List<Unsupported> unsupported = new ArrayList<>(componentLevel);

			unsupported.addAll(this.notes);

			// A trigger naming an event the file never defines is a typo the author cannot see:
			// nothing happens and nothing complains.
			for (String name : triggeredNames()) {
				if (!events.containsKey(name)) {
					unsupported.add(new Unsupported("event: " + name,
							"triggered but never defined in 'events' - nothing will happen", false));
				}
			}

			// Bedrock sound event names have no Java counterpart, and picking a plausible one would
			// play the wrong sound rather than none.
			for (String sound : soundEvents(events.values())) {
				unsupported.add(new Unsupported("sound_effect: " + sound,
						"Bedrock sound events have no Java equivalent - this will stay silent", true));
			}

			// A particle with no shape or no lifetime would spawn nothing, or spawn immortals —
			// both are almost certainly a truncated export rather than an intentional effect.
			if (this.shape == null)
				throw new KashiParticleParseException(EFFECT_KEY + ".components",
						"no 'minecraft:emitter_shape_*' component — the emitter has no shape to spawn from");

			if (this.particleLifetime == null)
				throw new KashiParticleParseException(EFFECT_KEY + ".components",
						"no 'minecraft:particle_lifetime_expression' component — particles would never expire");

			if (this.appearance == null)
				throw new KashiParticleParseException(EFFECT_KEY + ".components",
						"no 'minecraft:particle_appearance_billboard' component — particles would be invisible");

			// Rate and emitter lifetime do have sane Bedrock defaults, so fill them in rather
			// than refusing the import.
			EmitterRate resolvedRate = this.rate != null ? this.rate
					: new EmitterRate.Steady(MolangExpr.constant(1), MolangExpr.constant(50));
			EmitterLifetime resolvedLifetime = this.lifetime != null ? this.lifetime
					: new EmitterLifetime.Once(MolangExpr.constant(10));

			return new KashiParticleDefinition(identifier, render, resolvedRate, resolvedLifetime,
					this.shape, this.particleLifetime, this.initialSpin, this.initialSpeed, this.motion,
					this.appearance, this.tinting, this.emitterInit, this.particleInit,
					this.motionParametric, this.litByWorld, this.localSpace, curves, events,
					this.emitterEvents, this.particleEvents, this.collision, this.killPlane,
					new BlockFilter(this.expireInside, this.expireOutside),
					Collections.unmodifiableList(unsupported));
		}

		/** Every sound an event would play, found by walking the whole tree of nodes. */
		private static List<String> soundEvents(java.util.Collection<EventNode> nodes) {
			List<String> sounds = new ArrayList<>();

			for (EventNode node : nodes) {
				switch (node) {
					case EventNode.Sound sound -> sounds.add(sound.eventName());
					case EventNode.Sequence sequence -> sounds.addAll(soundEvents(sequence.nodes()));
					case EventNode.Randomize randomize -> sounds.addAll(soundEvents(
							randomize.options().stream().map(WeightedOption::node).toList()));
					default -> { }
				}
			}

			return sounds;
		}

		/** Every event name any trigger refers to, across both lifetime-event components. */
		private List<String> triggeredNames() {
			List<String> names = new ArrayList<>();

			for (LifetimeEvents events : List.of(this.emitterEvents, this.particleEvents)) {
				names.addAll(events.creation());
				names.addAll(events.expiration());
				names.addAll(events.travelDistanceLooping());
				events.timeline().forEach(entry -> names.addAll(entry.events()));
				events.travelDistance().forEach(entry -> names.addAll(entry.events()));
			}

			return names;
		}
	}

	// ------------------------------------------------------- component parts

	private static EmitterDirection direction(JsonObject owner, String path) {
		JsonElement element = owner.get("direction");

		if (element == null || element.isJsonNull())
			return new EmitterDirection.Relative(EmitterDirection.Mode.OUTWARDS);

		if (element.isJsonArray())
			return new EmitterDirection.Custom(vec3Array(element.getAsJsonArray(), path + ".direction"));

		String mode = element.getAsString().trim().toLowerCase(Locale.ROOT);

		return switch (mode) {
			case "outwards" -> new EmitterDirection.Relative(EmitterDirection.Mode.OUTWARDS);
			case "inwards" -> new EmitterDirection.Relative(EmitterDirection.Mode.INWARDS);
			default -> throw new KashiParticleParseException(path + ".direction",
					"expected 'outwards', 'inwards' or a [x, y, z] array, found '" + mode + "'");
		};
	}

	private static Vec3Expr planeNormal(JsonObject owner, String path) {
		JsonElement element = owner.get("plane_normal");

		if (element == null || element.isJsonNull())
			return new Vec3Expr(MolangExpr.constant(0), MolangExpr.constant(1), MolangExpr.constant(0));

		if (element.isJsonArray())
			return vec3Array(element.getAsJsonArray(), path + ".plane_normal");

		// Bedrock also accepts the shorthand axis names "x" / "y" / "z".
		return switch (element.getAsString().trim().toLowerCase(Locale.ROOT)) {
			case "x" -> new Vec3Expr(MolangExpr.constant(1), MolangExpr.constant(0), MolangExpr.constant(0));
			case "y" -> new Vec3Expr(MolangExpr.constant(0), MolangExpr.constant(1), MolangExpr.constant(0));
			case "z" -> new Vec3Expr(MolangExpr.constant(0), MolangExpr.constant(0), MolangExpr.constant(1));
			default -> throw new KashiParticleParseException(path + ".plane_normal",
					"expected 'x', 'y', 'z' or a [x, y, z] array");
		};
	}

	private static InitialSpeed initialSpeed(JsonElement element, String path) {
		if (element.isJsonArray())
			return new InitialSpeed.Velocity(vec3Array(element.getAsJsonArray(), path));

		return new InitialSpeed.AlongDirection(MolangExpr.from(element, path));
	}

	private static Appearance appearance(JsonObject owner, String path, List<Unsupported> notes) {
		Vec2Expr size = vec2(owner, "size", path + ".size", 1);
		FacingMode facing = facing(owner, path, notes);
		JsonObject uvObject = owner.getAsJsonObject("uv");

		if (uvObject == null) {
			// No uv block means the whole texture, unanimated.
			return new Appearance(size, facing, new Uv(1, 1,
					new Vec2Expr(MolangExpr.constant(0), MolangExpr.constant(0)),
					new Vec2Expr(MolangExpr.constant(1), MolangExpr.constant(1)), null));
		}

		String uvPath = path + ".uv";
		double width = number(uvObject, "texture_width", uvPath + ".texture_width", 1);
		double height = number(uvObject, "texture_height", uvPath + ".texture_height", 1);

		if (width <= 0 || height <= 0)
			throw new KashiParticleParseException(uvPath, "texture_width and texture_height must be positive");

		JsonObject flipbookObject = uvObject.getAsJsonObject("flipbook");
		Flipbook flipbook = flipbookObject == null
				? null : flipbook(flipbookObject, uvPath + ".flipbook", notes);

		return new Appearance(size, facing, new Uv(width, height,
				vec2(uvObject, "uv", uvPath + ".uv", 0),
				vec2(uvObject, "uv_size", uvPath + ".uv_size", 1), flipbook));
	}

	private static Flipbook flipbook(JsonObject owner, String path, List<Unsupported> notes) {
		double maxFrame = number(owner, "max_frame", path + ".max_frame", 1);
		boolean stretch = bool(owner, "stretch_to_lifetime", false);

		// Without stretch_to_lifetime the flipbook is driven by frames_per_second, so a missing
		// fps freezes the animation on frame 0. That is a still image, not a broken effect - worth
		// pointing out, not worth refusing an import over.
		if (!stretch && !owner.has("frames_per_second")) {
			notes.add(new Unsupported("flipbook without frames_per_second",
					"the animation has no frame rate and no stretch_to_lifetime, so it holds "
							+ "frame 0 for the whole life", false));
		}

		// These are MoLang, not plain numbers: real packs pick a starting frame with something like
		// "math.floor(v.particle_random_3 * 16) * 512", which parsing as a double rejects outright.
		return new Flipbook(
				vec2(owner, "base_UV", path + ".base_UV", 0),
				vec2(owner, "size_UV", path + ".size_UV", 1),
				vec2(owner, "step_UV", path + ".step_UV", 0),
				molang(owner, "frames_per_second", path + ".frames_per_second", 0),
				maxFrame, stretch, bool(owner, "loop", false));
	}

	private static FacingMode facing(JsonObject owner, String path, List<Unsupported> notes) {
		JsonElement element = owner.get("facing_camera_mode");

		if (element == null || element.isJsonNull())
			return FacingMode.ROTATE_XYZ;

		String mode = element.getAsString().trim().toUpperCase(Locale.ROOT);

		try {
			return FacingMode.valueOf(mode);
		} catch (IllegalArgumentException unknown) {
			// A facing mode this parser has not heard of is one field of one component; refusing
			// the whole effect over it throws away everything else that was fine. Fall back to the
			// camera-facing billboard, which is at least always visible, and say so.
			notes.add(new Unsupported("facing_camera_mode: " + element.getAsString(),
					"unknown facing mode - particles will face the camera (rotate_xyz) instead", false));

			return FacingMode.ROTATE_XYZ;
		}
	}

	private static Tinting tinting(JsonObject owner, String path) {
		JsonElement color = owner.get("color");

		if (color == null || color.isJsonNull())
			throw new KashiParticleParseException(path, "missing 'color'");

		// Flat colour: either "#RRGGBBAA" or [r, g, b, a].
		if (!color.isJsonObject())
			return new Tinting(null, null, colorExpr(color, path + ".color"));

		JsonObject colorObject = color.getAsJsonObject();
		JsonElement gradient = colorObject.get("gradient");

		if (gradient == null || gradient.isJsonNull())
			throw new KashiParticleParseException(path + ".color",
					"an object colour must carry a 'gradient'");

		return new Tinting(MolangExpr.from(colorObject.get("interpolant"), path + ".color.interpolant", 0),
				gradient(gradient, path + ".color.gradient"), null);
	}

	private static List<GradientStop> gradient(JsonElement element, String path) {
		List<GradientStop> stops = new ArrayList<>();

		if (element.isJsonArray()) {
			// Array form: stops are spread evenly across 0..1.
			JsonArray array = element.getAsJsonArray();

			if (array.isEmpty())
				throw new KashiParticleParseException(path, "gradient is empty");

			for (int i = 0; i < array.size(); i++) {
				double position = array.size() == 1 ? 0 : (double) i / (array.size() - 1);

				stops.add(stop(position, array.get(i), path + "[" + i + "]"));
			}
		} else if (element.isJsonObject()) {
			// Object form: the keys are the stop positions.
			for (Map.Entry<String, JsonElement> entry : element.getAsJsonObject().entrySet()) {
				double position;

				try {
					position = Double.parseDouble(entry.getKey());
				} catch (NumberFormatException notANumber) {
					throw new KashiParticleParseException(path,
							"gradient key '" + entry.getKey() + "' is not a number");
				}

				stops.add(stop(position, entry.getValue(), path + "." + entry.getKey()));
			}

			// JSON object order is not guaranteed to be sorted, and interpolation depends on it.
			stops.sort((a, b) -> Double.compare(a.position(), b.position()));
		} else {
			throw new KashiParticleParseException(path, "expected an array or an object of stops");
		}

		return Collections.unmodifiableList(stops);
	}

	private static GradientStop stop(double position, JsonElement value, String path) {
		ColorExpr color = colorExpr(value, path);

		// Gradient stops must be literal colours — they are sampled, not evaluated per-particle.
		if (!color.r().isConstant() || !color.g().isConstant() || !color.b().isConstant()
				|| !color.a().isConstant())
			throw new KashiParticleParseException(path, "gradient stops must be literal colours, "
					+ "not MoLang expressions");

		return new GradientStop(position, (float) color.r().constantValue(),
				(float) color.g().constantValue(), (float) color.b().constantValue(),
				(float) color.a().constantValue());
	}

	/**
	 * Reads a colour given either as a hex string or as an array of up to four MoLang channels.
	 *
	 * <p>Hex is {@code #RRGGBB} or {@code #AARRGGBB} — <b>alpha first</b>, the Snowstorm/Bedrock
	 * convention. This was verified against the reference effect: its gradient
	 * {@code "#FF00FF72"} renders green in Snowstorm, which only the alpha-first reading
	 * ({@code A=FF, R=00, G=FF, B=72}) produces; read alpha-last it would be magenta. The
	 * trailing {@code 72} in a stop like {@code "#0000FF72"} is therefore an alpha of ~0, i.e. the
	 * particle fades out at end of life — intended, not a mistake.
	 */
	private static ColorExpr colorExpr(JsonElement element, String path) {
		if (element.isJsonArray()) {
			JsonArray array = element.getAsJsonArray();

			if (array.size() < 3)
				throw new KashiParticleParseException(path,
						"a colour array needs at least [r, g, b], found " + array.size() + " entries");

			// Array form stays [r, g, b, a] — only the hex string is alpha-first.
			return new ColorExpr(MolangExpr.from(array.get(0), path + "[0]"),
					MolangExpr.from(array.get(1), path + "[1]"),
					MolangExpr.from(array.get(2), path + "[2]"),
					array.size() > 3 ? MolangExpr.from(array.get(3), path + "[3]") : MolangExpr.constant(1));
		}

		if (!(element instanceof JsonPrimitive primitive) || !primitive.isString())
			throw new KashiParticleParseException(path, "expected a '#AARRGGBB' string or a [r, g, b, a] array");

		String hex = primitive.getAsString().trim();

		if (hex.startsWith("#"))
			hex = hex.substring(1);

		if (hex.length() != 6 && hex.length() != 8)
			throw new KashiParticleParseException(path,
					"expected 6 or 8 hex digits, found '" + primitive.getAsString() + "'");

		try {
			// 8 digits are AARRGGBB (alpha first); 6 digits are RRGGBB with full alpha.
			int alphaOffset = hex.length() == 8 ? 2 : 0;

			return new ColorExpr(
					MolangExpr.constant(Integer.parseInt(hex.substring(alphaOffset, alphaOffset + 2), 16) / 255.0),
					MolangExpr.constant(Integer.parseInt(hex.substring(alphaOffset + 2, alphaOffset + 4), 16) / 255.0),
					MolangExpr.constant(Integer.parseInt(hex.substring(alphaOffset + 4, alphaOffset + 6), 16) / 255.0),
					MolangExpr.constant(hex.length() == 8
							? Integer.parseInt(hex.substring(0, 2), 16) / 255.0 : 1.0));
		} catch (NumberFormatException notHex) {
			throw new KashiParticleParseException(path,
					"'" + primitive.getAsString() + "' is not a hex colour", notHex);
		}
	}

	// ----------------------------------------------------------- json basics

	private static JsonObject obj(JsonObject owner, String key, String path) {
		JsonElement element = owner.get(key);

		if (element == null || !element.isJsonObject())
			throw new KashiParticleParseException(path, "expected an object");

		return element.getAsJsonObject();
	}

	private static JsonObject asObj(JsonElement element, String path) {
		if (!element.isJsonObject())
			throw new KashiParticleParseException(path, "expected an object");

		return element.getAsJsonObject();
	}

	private static String string(JsonObject owner, String key, String path) {
		JsonElement element = owner.get(key);

		if (element == null || !element.isJsonPrimitive())
			throw new KashiParticleParseException(path, "expected a string");

		return element.getAsString();
	}

	private static boolean bool(JsonObject owner, String key, boolean fallback) {
		JsonElement element = owner.get(key);

		return element == null || element.isJsonNull() ? fallback : element.getAsBoolean();
	}

	private static double number(JsonObject owner, String key, String path, double fallback) {
		JsonElement element = owner.get(key);

		if (element == null || element.isJsonNull())
			return fallback;

		if (!element.isJsonPrimitive())
			throw new KashiParticleParseException(path, "expected a number");

		return element.getAsDouble();
	}

	private static MolangExpr molang(JsonObject owner, String key, String path, double fallback) {
		return MolangExpr.from(owner.get(key), path, fallback);
	}

	private static double[] doubles(JsonObject owner, String key, String path, int size, double fallback) {
		JsonElement element = owner.get(key);
		double[] values = new double[size];

		if (element == null || element.isJsonNull()) {
			java.util.Arrays.fill(values, fallback);

			return values;
		}

		if (!element.isJsonArray() || element.getAsJsonArray().size() != size)
			throw new KashiParticleParseException(path, "expected an array of " + size + " numbers");

		for (int i = 0; i < size; i++)
			values[i] = element.getAsJsonArray().get(i).getAsDouble();

		return values;
	}

	private static Vec2Expr vec2(JsonObject owner, String key, String path, double fallback) {
		JsonElement element = owner.get(key);

		if (element == null || element.isJsonNull())
			return new Vec2Expr(MolangExpr.constant(fallback), MolangExpr.constant(fallback));

		if (!element.isJsonArray() || element.getAsJsonArray().size() != 2)
			throw new KashiParticleParseException(path, "expected an array of 2 values");

		JsonArray array = element.getAsJsonArray();

		return new Vec2Expr(MolangExpr.from(array.get(0), path + "[0]"),
				MolangExpr.from(array.get(1), path + "[1]"));
	}

	private static Vec3Expr vec3(JsonObject owner, String key, String path, double fallback) {
		JsonElement element = owner.get(key);

		if (element == null || element.isJsonNull())
			return new Vec3Expr(MolangExpr.constant(fallback), MolangExpr.constant(fallback),
					MolangExpr.constant(fallback));

		return vec3Array(element.isJsonArray() ? element.getAsJsonArray() : null, path);
	}

	private static Vec3Expr vec3Array(JsonArray array, String path) {
		if (array == null || array.size() != 3)
			throw new KashiParticleParseException(path, "expected an array of 3 values");

		return new Vec3Expr(MolangExpr.from(array.get(0), path + "[0]"),
				MolangExpr.from(array.get(1), path + "[1]"),
				MolangExpr.from(array.get(2), path + "[2]"));
	}
}
