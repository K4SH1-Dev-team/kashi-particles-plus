package net.kashi.particles.core.molang;

import net.kashi.particles.core.molang.MolangContext.Var;

import java.util.ArrayList;
import java.util.List;

/**
 * Checks the MoLang evaluator against Bedrock semantics as implemented by Wintersky, the
 * runtime behind Snowstorm.
 *
 * <p>Run via {@code tools/run-core-tests.ps1}.
 */
public final class MolangEvaluatorTest {

	private static final List<String> FAILURES = new ArrayList<>();
	private static int checks;

	public static void main(String[] args) {
		arithmeticAndPrecedence();
		trigonometryIsInDegrees();
		aliasesResolveToTheSameVariable();
		constantsAreFoldedButRandomIsNot();
		comparisonsAndTernaries();
		divisionByZeroYieldsZero();
		statementsAndAssignment();
		referenceEffectExpressions();
		badSyntaxIsReportedWithPosition();

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

	private static void arithmeticAndPrecedence() {
		near("addition", 7, eval("3 + 4"));
		near("precedence", 14, eval("2 + 3 * 4"));
		near("parentheses", 20, eval("(2 + 3) * 4"));
		near("unary minus", -5, eval("-5"));
		near("minus binds tighter than plus", 1, eval("3 + -2"));
		near("modulo", 1, eval("7 % 3"));
		near("nested unary", 5, eval("--5"));
	}

	/** Bedrock trigonometry takes and returns degrees, not radians. */
	private static void trigonometryIsInDegrees() {
		near("sin(90) = 1", 1, eval("math.sin(90)"));
		near("cos(0) = 1", 1, eval("math.cos(0)"));
		near("cos(180) = -1", -1, eval("math.cos(180)"));
		near("asin(1) = 90 degrees", 90, eval("math.asin(1)"));
		near("atan2 in degrees", 45, eval("math.atan2(1, 1)"));
		near("min_angle wraps to [-180,180]", -170, eval("math.min_angle(190)"));
		near("hermite_blend(0.5)", 0.5, eval("math.hermite_blend(0.5)"));
		near("lerp is unclamped", 20, eval("math.lerp(0, 10, 2)"));
	}

	/**
	 * The reference effect writes {@code variable.emitter_age} in one component and
	 * {@code v.particle_age} in another; both spellings must reach the same slot.
	 */
	private static void aliasesResolveToTheSameVariable() {
		MolangCompiler compiler = new MolangCompiler();
		MolangValue viaLongForm = compiler.compile("variable.particle_age");
		MolangValue viaAlias = compiler.compile("v.particle_age");
		MolangValue custom = compiler.compile("variable.my_thing + v.my_thing");
		MolangContext context = compiler.newContext();

		context.set(Var.PARTICLE_AGE, 0.25);

		near("variable.particle_age", 0.25, viaLongForm.eval(context));
		near("v.particle_age is the same slot", 0.25, viaAlias.eval(context));

		// A custom variable read through both spellings must also be one slot, not two.
		near("custom variable aliases share a slot", 0, custom.eval(context));
	}

	private static void constantsAreFoldedButRandomIsNot() {
		MolangCompiler compiler = new MolangCompiler();

		eq("pure arithmetic folds", true, compiler.compile("2 * 3 + 1").isConstant());
		eq("math on constants folds", true, compiler.compile("math.sqrt(16)").isConstant());
		eq("anything with a variable does not fold", false,
				compiler.compile("v.particle_age * 2").isConstant());

		// Bedrock re-rolls math.random on every evaluation. Folding it would freeze every
		// particle at one angle; freezing per particle is the engine's job, not the compiler's.
		MolangValue random = compiler.compile("math.random(0, 360)");
		eq("math.random never folds", false, random.isConstant());

		MolangContext context = compiler.newContext();
		boolean varies = false;

		for (int i = 0; i < 50 && !varies; i++)
			varies = random.eval(context) != random.eval(context);

		eq("math.random varies between evaluations", true, varies);

		double roll = random.eval(context);
		eq("math.random(0,360) stays in range", true, roll >= 0 && roll <= 360);
	}

	private static void comparisonsAndTernaries() {
		near("less than", 1, eval("1 < 2"));
		near("greater or equal", 0, eval("1 >= 2"));
		near("equality", 1, eval("2 == 2"));
		near("inequality", 1, eval("2 != 3"));
		near("logical and", 0, eval("1 && 0"));
		near("logical or", 1, eval("1 || 0"));
		near("negation", 1, eval("!0"));
		near("ternary true branch", 10, eval("1 ? 10 : 20"));
		near("ternary false branch", 20, eval("0 ? 10 : 20"));
		near("ternary without else yields 0", 0, eval("0 ? 10"));
	}

	/** Effects divide by age and lifetime freely; a crash mid-render would be worse than 0. */
	private static void divisionByZeroYieldsZero() {
		near("division by zero", 0, eval("5 / 0"));
		near("modulo by zero", 0, eval("5 % 0"));
	}

	private static void statementsAndAssignment() {
		near("last statement wins", 3, eval("1; 2; 3"));
		near("return stops evaluation", 2, eval("1; return 2; 3"));

		MolangCompiler compiler = new MolangCompiler();
		MolangValue assign = compiler.compile("variable.speed = 4; variable.speed * 2");

		near("assignment then read", 8, assign.eval(compiler.newContext()));
	}

	/** The actual expressions from the reference effect must compile and behave. */
	private static void referenceEffectExpressions() {
		MolangCompiler compiler = new MolangCompiler();

		MolangValue offsetX = compiler.compile(
				"math.cos(230+variable.emitter_age*800)*(1.5+variable.emitter_age*4)");
		MolangValue radius = compiler.compile("0.5+variable.emitter_age");
		MolangValue lifetime = compiler.compile("variable.particle_random_3 * 0.5");
		MolangValue size = compiler.compile(
				"0.2+variable.particle_random_1*0.2+(variable.emitter_age*0.5)");
		MolangValue interpolant = compiler.compile("v.particle_age / v.particle_lifetime");

		MolangContext context = compiler.newContext();

		context.set(Var.EMITTER_AGE, 0);
		near("radius at emitter age 0", 0.5, radius.eval(context));
		near("offset.x at emitter age 0", Math.cos(Math.toRadians(230)) * 1.5, offsetX.eval(context));

		context.set(Var.EMITTER_AGE, 0.5);
		near("radius at emitter age 0.5", 1.0, radius.eval(context));

		context.set(Var.PARTICLE_RANDOM_3, 0.8);
		near("max_lifetime", 0.4, lifetime.eval(context));

		context.set(Var.PARTICLE_RANDOM_1, 1);
		near("size.x", 0.2 + 0.2 + 0.25, size.eval(context));

		context.set(Var.PARTICLE_AGE, 1);
		context.set(Var.PARTICLE_LIFETIME, 4);
		near("tint interpolant", 0.25, interpolant.eval(context));

		// Before a lifetime is assigned the interpolant divides by zero every frame.
		context.set(Var.PARTICLE_LIFETIME, 0);
		near("interpolant survives a zero lifetime", 0, interpolant.eval(context));
	}

	private static void badSyntaxIsReportedWithPosition() {
		rejects("unknown function", "math.bogus(1)", "unknown function");
		rejects("unknown identifier", "bogus.thing", "unknown identifier");
		rejects("wrong arity", "math.cos(1, 2)", "takes 1 argument");
		rejects("unclosed paren", "(1 + 2", "expected ')'");
		rejects("stray character", "1 $ 2", "unexpected character");
	}

	// ---------------------------------------------------------------- harness

	private static double eval(String expression) {
		MolangCompiler compiler = new MolangCompiler();

		return compiler.compile(expression).eval(compiler.newContext());
	}

	private static void rejects(String what, String expression, String expectedFragment) {
		checks++;

		try {
			new MolangCompiler().compile(expression);
			FAILURES.add(what + ": expected a compile failure, but '" + expression + "' was accepted");
		} catch (MolangSyntaxException expected) {
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

		if (Math.abs(expected - actual) < 1e-9) {
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
