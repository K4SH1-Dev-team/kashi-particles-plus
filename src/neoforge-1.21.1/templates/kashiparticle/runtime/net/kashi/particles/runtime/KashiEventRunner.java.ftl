package net.kashi.particles.runtime;

import net.kashi.particles.core.KashiParticleDefinition;
import net.kashi.particles.core.KashiParticleDefinition.EventNode;
import net.kashi.particles.core.molang.MolangContext;

import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.world.entity.Entity;

import java.util.List;

/**
 * Fires a named event from a {@code .particle.json} â€” Snowstorm's Events tab.
 *
 * <p>An event is how one effect starts another: a slash spawns its own sparks, which spawn their
 * own smoke. That makes it the one part of an effect that can spawn work without bound, so the
 * chain is depth-limited rather than trusted.
 *
 * <p>Events run entirely client-side, inside the particle engine's tick. Nothing here goes back
 * through the spawn packet: the effect being started is already compiled and present.
 */
final class KashiEventRunner {

	private KashiEventRunner() {
	}

	/**
	 * How deep one effect may chain into another.
	 *
	 * <p>An effect whose creation event spawns itself is a legal file and an infinite loop, and it
	 * would spawn until the client dies rather than misbehaving visibly. Four is well past what any
	 * hand-authored chain needs.
	 */
	private static final int MAX_DEPTH = 4;

	/**
	 * Runs every event in {@code names}.
	 *
	 * @param context the MoLang context of whatever fired this â€” the emitter for an emitter event,
	 *                the particle for a particle one, so an expression node writes where it should
	 * @param anchor  the entity the firing effect follows, passed on so a bound child follows it too
	 * @param depth   how many events deep this already is
	 */
	static void fire(KashiCompiledEffect source, List<String> names, MolangContext context,
			ClientLevel level, double x, double y, double z,
			double dirX, double dirY, double dirZ, Entity anchor, int depth) {
		if (names.isEmpty() || depth >= MAX_DEPTH)
			return;

		for (String name : names) {
			EventNode node = source.definition().events().get(name);

			// A trigger naming an event the file never defines is already reported at import; here
			// it is simply nothing to do.
			if (node != null)
				run(source, node, context, level, x, y, z, dirX, dirY, dirZ, anchor, depth);
		}
	}

	private static void run(KashiCompiledEffect source, EventNode node, MolangContext context,
			ClientLevel level, double x, double y, double z,
			double dirX, double dirY, double dirZ, Entity anchor, int depth) {
		switch (node) {
			case EventNode.Sequence sequence -> {
				for (EventNode child : sequence.nodes())
					run(source, child, context, level, x, y, z, dirX, dirY, dirZ, anchor, depth);
			}
			case EventNode.Randomize randomize -> {
				EventNode picked = pick(randomize, level);

				if (picked != null)
					run(source, picked, context, level, x, y, z, dirX, dirY, dirZ, anchor, depth);
			}
			case EventNode.Expression expression ->
					source.compile(expression.expression()).eval(context);
			case EventNode.Effect effect ->
					spawn(source, effect, context, level, x, y, z, dirX, dirY, dirZ, anchor, depth);
			// A Bedrock sound event name has no Java counterpart to map onto, and guessing one
			// would play the wrong sound rather than none. Reported at import instead.
			case EventNode.Sound sound -> { }
			case EventNode.Log log -> { }
		}
	}

	private static void spawn(KashiCompiledEffect source, EventNode.Effect effect,
			MolangContext context, ClientLevel level, double x, double y, double z,
			double dirX, double dirY, double dirZ, Entity anchor, int depth) {
		// Runs before the spawn and in the firing effect's own context, which is the point: it is
		// how an effect passes a value to the one it is about to start.
		source.compile(effect.preEffectExpression()).eval(context);

		KashiCompiledEffect target = KashiParticleRegistry.byIdentifier(effect.effect());

		if (target == null)
			return; // that effect was not imported; the rest of this event still runs

		// The child inherits the aim so a chained effect leans the way its parent was fired, and
		// the anchor only when bound - an unbound child is left where it was born, which is the
		// whole difference between the two types.
		boolean bound = effect.type() == KashiParticleDefinition.EffectType.EMITTER_BOUND;

		Minecraft.getInstance().particleEngine.add(new KashiEmitterParticle(level, x, y, z, target,
				dirX, dirY, dirZ, bound ? anchor : null, depth + 1));
	}

	/** Picks one option by weight, the way Wintersky's {@code getRandomFromWeightedList} does. */
	private static EventNode pick(EventNode.Randomize randomize, ClientLevel level) {
		double total = 0;

		for (KashiParticleDefinition.Weighted option : randomize.options())
			total += Math.max(0, option.weight());

		if (total <= 0)
			return randomize.options().isEmpty() ? null : randomize.options().get(0).node();

		double roll = level.random.nextDouble() * total;

		for (KashiParticleDefinition.Weighted option : randomize.options()) {
			roll -= Math.max(0, option.weight());

			if (roll <= 0)
				return option.node();
		}

		return randomize.options().get(randomize.options().size() - 1).node();
	}
}
