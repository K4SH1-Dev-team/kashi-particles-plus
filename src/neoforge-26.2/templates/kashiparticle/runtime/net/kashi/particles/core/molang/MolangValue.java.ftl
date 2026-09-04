package net.kashi.particles.core.molang;

/**
 * A compiled MoLang expression, ready to be evaluated against a {@link MolangContext}.
 *
 * <p>Compilation happens once per effect at import; evaluation happens per particle per tick,
 * so implementations must not allocate.
 */
@FunctionalInterface
public interface MolangValue {

	double eval(MolangContext context);

	/**
	 * Whether this expression always yields the same number and can be evaluated once at
	 * import instead of every tick.
	 *
	 * <p>Notably false for anything containing {@code math.random}, which Bedrock re-rolls on
	 * every evaluation.
	 */
	default boolean isConstant() {
		return false;
	}
}
