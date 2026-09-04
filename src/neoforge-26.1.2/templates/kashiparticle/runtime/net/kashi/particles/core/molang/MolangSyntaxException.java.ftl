package net.kashi.particles.core.molang;

/** Thrown when a MoLang expression cannot be compiled, pointing at the offending position. */
public class MolangSyntaxException extends RuntimeException {

	public MolangSyntaxException(String expression, int position, String message) {
		super(message + "\n  " + expression + "\n  " + " ".repeat(Math.max(0, position)) + "^");
	}
}
