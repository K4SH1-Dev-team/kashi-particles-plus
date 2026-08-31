package net.kashi.particles.core.molang;

/**
 * The variable state a compiled MoLang expression reads from.
 *
 * <p>One context belongs to one particle (or to the emitter itself). Unlike GeckoLib's global
 * static variable registry, nothing here is shared between particles, so evaluation carries no
 * ordering hazard and the engine never has to reset state between particles.
 *
 * <p>The well-known Bedrock variables live in a fixed array indexed by {@link Var}; anything the
 * effect invents for itself gets a slot allocated by {@link MolangCompiler} at compile time.
 * Both are plain array reads at evaluation time.
 */
public final class MolangContext {

	/**
	 * The variables every Bedrock particle effect can rely on.
	 *
	 * <p>Names are the canonical {@code variable.} spelling; the compiler folds the {@code v.}
	 * alias onto these before lookup.
	 */
	public enum Var {
		PARTICLE_AGE("variable.particle_age"),
		PARTICLE_LIFETIME("variable.particle_lifetime"),
		PARTICLE_RANDOM_1("variable.particle_random_1"),
		PARTICLE_RANDOM_2("variable.particle_random_2"),
		PARTICLE_RANDOM_3("variable.particle_random_3"),
		PARTICLE_RANDOM_4("variable.particle_random_4"),
		EMITTER_AGE("variable.emitter_age"),
		EMITTER_LIFETIME("variable.emitter_lifetime"),
		EMITTER_RANDOM_1("variable.emitter_random_1"),
		EMITTER_RANDOM_2("variable.emitter_random_2"),
		EMITTER_RANDOM_3("variable.emitter_random_3"),
		EMITTER_RANDOM_4("variable.emitter_random_4"),
		ENTITY_SCALE("variable.entity_scale");

		final String canonicalName;

		Var(String canonicalName) {
			this.canonicalName = canonicalName;
		}

		/** The {@code variable.} spelling, for callers outside this package that match on names. */
		public String canonicalName() {
			return this.canonicalName;
		}
	}

	private static final Var[] VALUES = Var.values();

	private final double[] standard = new double[VALUES.length];

	/**
	 * Not final, and grown on demand: a context is sized from the slots the compiler had allocated
	 * when it was handed out, and an expression compiled later can introduce another one. Growing
	 * beats the alternative of an index-out-of-bounds crash mid-render.
	 */
	private double[] custom;

	MolangContext(int customSlots) {
		this.custom = new double[customSlots];
		this.standard[Var.ENTITY_SCALE.ordinal()] = 1;
	}

	public double get(Var variable) {
		return this.standard[variable.ordinal()];
	}

	public void set(Var variable, double value) {
		this.standard[variable.ordinal()] = value;
	}

	double getCustom(int slot) {
		return slot < this.custom.length ? this.custom[slot] : 0;
	}

	void setCustom(int slot, double value) {
		setVariable(slot, value);
	}

	/**
	 * Writes a custom {@code variable.*} by the slot {@code MolangCompiler.slotOf} reserved for it.
	 *
	 * <p>Public because curves live outside the expression language but must land in the same
	 * storage the expressions read.
	 */
	public void setVariable(int slot, double value) {
		if (slot >= this.custom.length)
			this.custom = java.util.Arrays.copyOf(this.custom, slot + 1);

		this.custom[slot] = value;
	}

	/**
	 * Copies the emitter-scoped variables into this context.
	 *
	 * <p>Called when a particle is born so that expressions reading {@code variable.emitter_age}
	 * see the emitter's clock, and again each tick because the emitter keeps ageing while the
	 * particle lives.
	 */
	/**
	 * Copies the emitter's custom {@code variable.*} values into this context.
	 *
	 * <p>Variables an effect declares in {@code emitter_initialization} are emitter-scoped but
	 * readable by its particles, so a particle starts from a snapshot of them. It is a snapshot,
	 * not a live link: a particle may then overwrite one for itself without disturbing the emitter.
	 */
	public void copyCustomFrom(MolangContext emitter) {
		System.arraycopy(emitter.custom, 0, this.custom, 0,
				Math.min(emitter.custom.length, this.custom.length));
	}

	public void inheritEmitterState(MolangContext emitter) {
		this.standard[Var.EMITTER_AGE.ordinal()] = emitter.standard[Var.EMITTER_AGE.ordinal()];
		this.standard[Var.EMITTER_LIFETIME.ordinal()] = emitter.standard[Var.EMITTER_LIFETIME.ordinal()];
		this.standard[Var.EMITTER_RANDOM_1.ordinal()] = emitter.standard[Var.EMITTER_RANDOM_1.ordinal()];
		this.standard[Var.EMITTER_RANDOM_2.ordinal()] = emitter.standard[Var.EMITTER_RANDOM_2.ordinal()];
		this.standard[Var.EMITTER_RANDOM_3.ordinal()] = emitter.standard[Var.EMITTER_RANDOM_3.ordinal()];
		this.standard[Var.EMITTER_RANDOM_4.ordinal()] = emitter.standard[Var.EMITTER_RANDOM_4.ordinal()];
		this.standard[Var.ENTITY_SCALE.ordinal()] = emitter.standard[Var.ENTITY_SCALE.ordinal()];
	}
}
