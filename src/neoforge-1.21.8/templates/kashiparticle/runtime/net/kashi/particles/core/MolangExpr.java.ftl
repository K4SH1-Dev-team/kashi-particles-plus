package net.kashi.particles.core;

import com.google.gson.JsonElement;
import com.google.gson.JsonPrimitive;

import net.kashi.particles.core.molang.MolangCompiler;
import net.kashi.particles.core.molang.MolangValue;

/**
 * A MoLang expression exactly as it appeared in the {@code .particle.json}.
 *
 * <p>Milestone 1 stores only the raw source, plus a pre-resolved value for the common case
 * where the JSON held a plain number. Compilation and evaluation arrive in milestone 2 —
 * nothing here evaluates anything.
 *
 * <p>The source is kept verbatim, aliases and all. Bedrock lets {@code v.} stand in for
 * {@code variable.} (and {@code q.} for {@code query.}), and the example effects mix both
 * spellings freely; resolving that alias is the evaluator's job, not the parser's, so that
 * error messages can quote back what the author actually wrote.
 */
public final class MolangExpr {

	private final String source;
	private final boolean constant;
	private final double constantValue;
	private MolangValue compiled;

	private MolangExpr(String source, boolean constant, double constantValue) {
		this.source = source;
		this.constant = constant;
		this.constantValue = constantValue;
	}

	public static MolangExpr constant(double value) {
		return new MolangExpr(Double.toString(value), true, value);
	}

	public static MolangExpr of(String source) {
		String trimmed = source.trim();

		try {
			return new MolangExpr(trimmed, true, Double.parseDouble(trimmed));
		} catch (NumberFormatException notANumber) {
			return new MolangExpr(trimmed, false, 0);
		}
	}

	/**
	 * Reads a MoLang value that Bedrock allows to be either a JSON number or a JSON string.
	 */
	public static MolangExpr from(JsonElement element, String path) {
		if (element == null || element.isJsonNull())
			throw new KashiParticleParseException(path, "expected a number or MoLang string, found nothing");

		if (!(element instanceof JsonPrimitive primitive) || primitive.isBoolean())
			throw new KashiParticleParseException(path,
					"expected a number or MoLang string, found " + element);

		return primitive.isNumber() ? constant(primitive.getAsDouble()) : of(primitive.getAsString());
	}

	public static MolangExpr from(JsonElement element, String path, double fallback) {
		return element == null || element.isJsonNull() ? constant(fallback) : from(element, path);
	}

	/**
	 * Compiles this expression, or returns the already-compiled tree.
	 *
	 * <p>All expressions of one effect must be compiled by the <em>same</em> compiler, so that
	 * they share its slot table and agree on where each custom variable lives.
	 */
	public MolangValue compile(MolangCompiler compiler) {
		if (this.compiled == null)
			this.compiled = compiler.compile(this.source);

		return this.compiled;
	}

	public String source() {
		return this.source;
	}

	/**
	 * Whether this expression resolved to a literal number and can skip evaluation entirely.
	 */
	public boolean isConstant() {
		return this.constant;
	}

	public double constantValue() {
		if (!this.constant)
			throw new IllegalStateException("not a constant: " + this.source);

		return this.constantValue;
	}

	@Override public String toString() {
		return this.constant ? Double.toString(this.constantValue) : "`" + this.source + "`";
	}
}
