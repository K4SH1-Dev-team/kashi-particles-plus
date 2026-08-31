package net.kashi.particles.runtime;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import net.kashi.particles.core.KashiParticleDefinition;

import net.minecraft.resources.ResourceLocation;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * The set of compiled KASHI effects a mod knows about, keyed by effect id.
 *
 * <p>Populated once at client start-up: each imported effect's {@code .particle.json} is parsed
 * and compiled, and its texture location recorded. A spawn names an effect by id, and the particle
 * provider looks it up here.
 *
 * <p>Effects live only on the client because rendering is client-side; the server never needs the
 * compiled form, only the id it puts into the spawn packet.
 */
public final class KashiParticleRegistry {

	private static final Map<ResourceLocation, KashiCompiledEffect> EFFECTS = new ConcurrentHashMap<>();

	private KashiParticleRegistry() {
	}

	public static void register(ResourceLocation id, KashiCompiledEffect effect) {
		EFFECTS.put(id, effect);
	}

	public static KashiCompiledEffect get(ResourceLocation id) {
		KashiCompiledEffect effect = EFFECTS.get(id);

		return effect != null ? effect : ALIASES.get(id);
	}

	/**
	 * Resolves the Bedrock identifier one effect uses to name another, as in an event's
	 * {@code "effect": "akaza:compass5"}.
	 *
	 * @return null if that effect was never imported, which is not an error - the author may have
	 *         imported only part of a pack
	 */
	public static KashiCompiledEffect byIdentifier(String identifier) {
		ResourceLocation id = ResourceLocation.tryParse(identifier);

		return id == null ? null : get(id);
	}

	/** Bedrock identifiers, kept apart from {@link #EFFECTS} so {@link #ids()} stays the real set. */
	private static final Map<ResourceLocation, KashiCompiledEffect> ALIASES = new ConcurrentHashMap<>();

	public static boolean contains(ResourceLocation id) {
		return EFFECTS.containsKey(id);
	}

	/** Every registered effect id, for command completion and "unknown effect" messages. */
	public static java.util.Set<ResourceLocation> ids() {
		return EFFECTS.keySet();
	}

	/**
	 * Parses and compiles an effect bundled on the classpath.
	 *
	 * @param id           the effect id a spawn will name
	 * @param jsonResource classpath path to the {@code .particle.json}, e.g.
	 *                     {@code /kashi_particles/demo_slash.particle.json}
	 * @param texture      where the effect's PNG lives in the mod assets
	 */
	public static void loadFromClasspath(ResourceLocation id, String jsonResource, ResourceLocation texture) {
		try (InputStream in = KashiParticleRegistry.class.getResourceAsStream(jsonResource)) {
			if (in == null)
				throw new IllegalStateException("bundled particle not found on classpath: " + jsonResource);

			JsonObject root = JsonParser.parseReader(
					new InputStreamReader(in, StandardCharsets.UTF_8)).getAsJsonObject();
			KashiParticleDefinition definition = KashiParticleDefinition.parse(root);
			KashiCompiledEffect compiled = KashiCompiledEffect.compile(definition, texture);

			register(id, compiled);

			// Also under its Bedrock identifier, because that is the name events use to refer to
			// one another: an effect whose creation_event spawns "akaza:compass5" knows nothing
			// about what the element ended up being called in the workspace. Registering both means
			// a chained effect resolves as long as it was imported, with nothing to configure.
			ResourceLocation bedrockId = ResourceLocation.tryParse(definition.identifier());

			if (bedrockId != null && !bedrockId.equals(id))
				ALIASES.put(bedrockId, compiled);
		} catch (Exception failure) {
			// One malformed effect must not take the others with it. Registration runs at client
			// start-up, so throwing here would be a crash before the main menu - and the mod may
			// hold a hundred effects of which this is the only broken one. The failure is logged
			// with its id; a spawn naming it will find nothing and quietly do nothing.
			FAILURES.put(id, failure.getMessage() == null ? failure.toString() : failure.getMessage());

			LOGGER.error("KASHI effect '{}' from {} could not be loaded and will not play", id,
					jsonResource, failure);
		}
	}

	/** Effects that failed to load, by id, with the reason. Empty when everything loaded. */
	public static Map<ResourceLocation, String> failures() {
		return FAILURES;
	}

	private static final Map<ResourceLocation, String> FAILURES = new ConcurrentHashMap<>();

	private static final org.slf4j.Logger LOGGER = com.mojang.logging.LogUtils.getLogger();
}
