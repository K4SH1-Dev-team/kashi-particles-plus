package net.kashi.particles.core.molang;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;

/**
 * Compiles MoLang source into an evaluable {@link MolangValue} tree.
 *
 * <p>One compiler instance serves one particle effect: it owns the slot table for whatever
 * variables that effect invents, so every expression in the effect agrees on where
 * {@code variable.my_thing} lives. Call {@link #newContext()} to get matching storage.
 *
 * <p>Semantics follow Bedrock as implemented by Wintersky, the runtime behind Snowstorm. The
 * details that matter and are easy to get wrong: trigonometry is in <b>degrees</b>, and
 * {@code math.random} re-rolls on every evaluation rather than being fixed per particle —
 * freezing a random value is the caller's job, done by evaluating spawn expressions once.
 */
public final class MolangCompiler {

	private final Map<String, Integer> customSlots = new HashMap<>();

	/** Storage sized for every custom variable seen so far. */
	public MolangContext newContext() {
		return new MolangContext(this.customSlots.size());
	}

	/**
	 * Reserves the slot a named {@code variable.*} lives in, so something outside the expression
	 * language — a curve — can write to the same place an expression reads from.
	 *
	 * @throws MolangSyntaxException if the name is one of Bedrock's built-in variables, which are
	 *                               driven by the runtime and must not be overwritten
	 */
	public int slotOf(String variableName) {
		String canonical = canonical(variableName);

		for (MolangContext.Var variable : MolangContext.Var.values()) {
			if (variable.canonicalName.equals(canonical))
				throw new MolangSyntaxException(variableName, 0,
						"'" + variableName + "' is a built-in Bedrock variable and cannot be "
								+ "assigned by a curve");
		}

		if (!canonical.startsWith("variable."))
			throw new MolangSyntaxException(variableName, 0,
					"a curve must be named 'variable.something', found '" + variableName + "'");

		return this.customSlots.computeIfAbsent(canonical, key -> this.customSlots.size());
	}

	public MolangValue compile(String source) {
		List<Token> tokens = tokenize(source);
		Parser parser = new Parser(source, tokens);
		MolangValue value = parser.parseProgram();

		return value.isConstant() ? constant(value.eval(newContext())) : value;
	}

	// ------------------------------------------------------------- tokenizer

	private enum Kind { NUMBER, IDENT, OP, LPAREN, RPAREN, COMMA, SEMICOLON, EOF }

	private record Token(Kind kind, String text, double number, int position) {}

	/** Multi-character operators, longest first so that {@code <=} never lexes as {@code <}. */
	private static final String[] OPERATORS = {
			"<=", ">=", "==", "!=", "&&", "||", "??",
			"+", "-", "*", "/", "%", "<", ">", "=", "!", "?", ":"
	};

	private static List<Token> tokenize(String source) {
		List<Token> tokens = new ArrayList<>();
		int i = 0;

		while (i < source.length()) {
			char c = source.charAt(i);

			if (Character.isWhitespace(c)) {
				i++;
				continue;
			}

			if (c == '(') {
				tokens.add(new Token(Kind.LPAREN, "(", 0, i++));
				continue;
			}

			if (c == ')') {
				tokens.add(new Token(Kind.RPAREN, ")", 0, i++));
				continue;
			}

			if (c == ',') {
				tokens.add(new Token(Kind.COMMA, ",", 0, i++));
				continue;
			}

			if (c == ';') {
				tokens.add(new Token(Kind.SEMICOLON, ";", 0, i++));
				continue;
			}

			if (Character.isDigit(c) || (c == '.' && i + 1 < source.length()
					&& Character.isDigit(source.charAt(i + 1)))) {
				int start = i;

				while (i < source.length() && (Character.isDigit(source.charAt(i)) || source.charAt(i) == '.'))
					i++;

				String text = source.substring(start, i);

				try {
					tokens.add(new Token(Kind.NUMBER, text, Double.parseDouble(text), start));
				} catch (NumberFormatException malformed) {
					throw new MolangSyntaxException(source, start, "malformed number '" + text + "'");
				}

				continue;
			}

			if (Character.isLetter(c) || c == '_') {
				int start = i;

				// Identifiers carry their namespace: "variable.particle_age", "math.cos".
				while (i < source.length() && (Character.isLetterOrDigit(source.charAt(i))
						|| source.charAt(i) == '_' || source.charAt(i) == '.'))
					i++;

				tokens.add(new Token(Kind.IDENT, source.substring(start, i), 0, start));
				continue;
			}

			String operator = null;

			for (String candidate : OPERATORS) {
				if (source.startsWith(candidate, i)) {
					operator = candidate;
					break;
				}
			}

			if (operator == null)
				throw new MolangSyntaxException(source, i, "unexpected character '" + c + "'");

			tokens.add(new Token(Kind.OP, operator, 0, i));
			i += operator.length();
		}

		tokens.add(new Token(Kind.EOF, "", 0, source.length()));

		return tokens;
	}

	// ---------------------------------------------------------------- parser

	private final class Parser {

		private final String source;
		private final List<Token> tokens;
		private int index;

		Parser(String source, List<Token> tokens) {
			this.source = source;
			this.tokens = tokens;
		}

		/**
		 * A MoLang "program" is one or more {@code ;}-separated statements; the value of the
		 * last one (or of an explicit {@code return}) is the result.
		 */
		MolangValue parseProgram() {
			List<MolangValue> statements = new ArrayList<>();

			while (!check(Kind.EOF)) {
				if (match(Kind.SEMICOLON))
					continue;

				boolean isReturn = check(Kind.IDENT) && peek().text().equals("return");

				if (isReturn)
					advance();

				statements.add(parseStatement());

				if (isReturn)
					break;
			}

			if (statements.isEmpty())
				throw new MolangSyntaxException(this.source, 0, "empty expression");

			if (statements.size() == 1)
				return statements.get(0);

			MolangValue[] compiled = statements.toArray(new MolangValue[0]);

			return context -> {
				double result = 0;

				for (MolangValue statement : compiled)
					result = statement.eval(context);

				return result;
			};
		}

		private MolangValue parseStatement() {
			// Assignment, as used by emitter_initialization's creation_expression.
			if (check(Kind.IDENT) && checkNext(Kind.OP, "=")) {
				String name = advance().text();

				advance();

				int slot = slotFor(canonical(name), peek().position());
				MolangValue value = parseExpression();

				return context -> {
					double result = value.eval(context);

					context.setCustom(slot, result);

					return result;
				};
			}

			return parseExpression();
		}

		private MolangValue parseExpression() {
			return parseTernary();
		}

		private MolangValue parseTernary() {
			MolangValue condition = parseCoalesce();

			if (!match(Kind.OP, "?"))
				return condition;

			MolangValue ifTrue = parseExpression();

			// Bedrock allows "a ? b" with no else branch, yielding 0 when the test fails.
			MolangValue ifFalse = match(Kind.OP, ":") ? parseExpression() : constant(0);

			return fold(condition, ifTrue, ifFalse,
					context -> condition.eval(context) != 0 ? ifTrue.eval(context) : ifFalse.eval(context));
		}

		private MolangValue parseCoalesce() {
			MolangValue left = parseOr();

			while (match(Kind.OP, "??")) {
				MolangValue right = parseOr();
				MolangValue target = left;

				// Nothing in a particle effect is ever truly "null", so this degrades to a
				// NaN/infinity guard, which is the useful reading in a numeric-only language.
				left = fold(target, right, context -> {
					double value = target.eval(context);

					return Double.isFinite(value) ? value : right.eval(context);
				});
			}

			return left;
		}

		private MolangValue parseOr() {
			MolangValue left = parseAnd();

			while (match(Kind.OP, "||")) {
				MolangValue right = parseAnd();
				MolangValue target = left;

				left = fold(target, right,
						context -> target.eval(context) != 0 || right.eval(context) != 0 ? 1 : 0);
			}

			return left;
		}

		private MolangValue parseAnd() {
			MolangValue left = parseEquality();

			while (match(Kind.OP, "&&")) {
				MolangValue right = parseEquality();
				MolangValue target = left;

				left = fold(target, right,
						context -> target.eval(context) != 0 && right.eval(context) != 0 ? 1 : 0);
			}

			return left;
		}

		private MolangValue parseEquality() {
			MolangValue left = parseComparison();

			while (check(Kind.OP, "==") || check(Kind.OP, "!=")) {
				boolean negate = advance().text().equals("!=");
				MolangValue right = parseComparison();
				MolangValue target = left;

				left = fold(target, right,
						context -> (target.eval(context) == right.eval(context)) != negate ? 1 : 0);
			}

			return left;
		}

		private MolangValue parseComparison() {
			MolangValue left = parseAdditive();

			while (check(Kind.OP, "<") || check(Kind.OP, "<=")
					|| check(Kind.OP, ">") || check(Kind.OP, ">=")) {
				String operator = advance().text();
				MolangValue right = parseAdditive();
				MolangValue target = left;

				left = fold(target, right, switch (operator) {
					case "<" -> context -> target.eval(context) < right.eval(context) ? 1 : 0;
					case "<=" -> context -> target.eval(context) <= right.eval(context) ? 1 : 0;
					case ">" -> context -> target.eval(context) > right.eval(context) ? 1 : 0;
					default -> context -> target.eval(context) >= right.eval(context) ? 1 : 0;
				});
			}

			return left;
		}

		private MolangValue parseAdditive() {
			MolangValue left = parseMultiplicative();

			while (check(Kind.OP, "+") || check(Kind.OP, "-")) {
				boolean plus = advance().text().equals("+");
				MolangValue right = parseMultiplicative();
				MolangValue target = left;

				left = fold(target, right, plus
						? context -> target.eval(context) + right.eval(context)
						: context -> target.eval(context) - right.eval(context));
			}

			return left;
		}

		private MolangValue parseMultiplicative() {
			MolangValue left = parseUnary();

			while (check(Kind.OP, "*") || check(Kind.OP, "/") || check(Kind.OP, "%")) {
				String operator = advance().text();
				MolangValue right = parseUnary();
				MolangValue target = left;

				left = fold(target, right, switch (operator) {
					case "*" -> context -> target.eval(context) * right.eval(context);
					case "/" -> context -> {
						double divisor = right.eval(context);

						// Bedrock effects divide by age and lifetime freely; a hard failure
						// mid-render would be worse than yielding zero.
						return divisor == 0 ? 0 : target.eval(context) / divisor;
					};
					default -> context -> {
						double divisor = right.eval(context);

						return divisor == 0 ? 0 : target.eval(context) % divisor;
					};
				});
			}

			return left;
		}

		private MolangValue parseUnary() {
			if (match(Kind.OP, "-")) {
				MolangValue operand = parseUnary();

				return fold(operand, context -> -operand.eval(context));
			}

			if (match(Kind.OP, "!")) {
				MolangValue operand = parseUnary();

				return fold(operand, context -> operand.eval(context) == 0 ? 1 : 0);
			}

			return parsePrimary();
		}

		private MolangValue parsePrimary() {
			Token token = advance();

			return switch (token.kind()) {
				case NUMBER -> constant(token.number());
				case LPAREN -> {
					MolangValue inner = parseExpression();

					expect(Kind.RPAREN, ")");

					yield inner;
				}
				case IDENT -> identifier(token);
				default -> throw new MolangSyntaxException(this.source, token.position(),
						"expected a value, found '" + token.text() + "'");
			};
		}

		private MolangValue identifier(Token token) {
			String name = token.text();
			String lower = name.toLowerCase(Locale.ROOT);

			if (lower.startsWith("math.")) {
				List<MolangValue> arguments = new ArrayList<>();

				if (match(Kind.LPAREN) && !match(Kind.RPAREN)) {
					do {
						arguments.add(parseExpression());
					} while (match(Kind.COMMA));

					expect(Kind.RPAREN, ")");
				}

				return MolangFunctions.build(lower, arguments, this.source, token.position());
			}

			String canonical = canonical(name);

			for (MolangContext.Var variable : MolangContext.Var.values()) {
				if (variable.canonicalName.equals(canonical))
					return context -> context.get(variable);
			}

			int slot = slotFor(canonical, token.position());

			return context -> context.getCustom(slot);
		}

		private int slotFor(String canonicalName, int position) {
			if (!canonicalName.startsWith("variable.") && !canonicalName.startsWith("query.")
					&& !canonicalName.startsWith("temp."))
				throw new MolangSyntaxException(this.source, position,
						"unknown identifier '" + canonicalName + "' - expected a math.* function "
								+ "or a variable./query./temp. name");

			return MolangCompiler.this.customSlots.computeIfAbsent(canonicalName,
					key -> MolangCompiler.this.customSlots.size());
		}

		// -------------------------------------------------------- token cursor

		private Token peek() {
			return this.tokens.get(this.index);
		}

		private Token advance() {
			return this.tokens.get(this.index++);
		}

		private boolean check(Kind kind) {
			return peek().kind() == kind;
		}

		private boolean check(Kind kind, String text) {
			return peek().kind() == kind && peek().text().equals(text);
		}

		private boolean checkNext(Kind kind, String text) {
			Token next = this.tokens.get(Math.min(this.index + 1, this.tokens.size() - 1));

			return next.kind() == kind && next.text().equals(text);
		}

		private boolean match(Kind kind) {
			if (!check(kind))
				return false;

			this.index++;

			return true;
		}

		private boolean match(Kind kind, String text) {
			if (!check(kind, text))
				return false;

			this.index++;

			return true;
		}

		private void expect(Kind kind, String what) {
			if (!match(kind))
				throw new MolangSyntaxException(this.source, peek().position(),
						"expected '" + what + "', found '" + peek().text() + "'");
		}
	}

	// -------------------------------------------------------------- folding

	/**
	 * Folds {@code v.} onto {@code variable.} and {@code q.} onto {@code query.}.
	 *
	 * <p>Bedrock treats these as the same name and real effects mix both spellings in one file —
	 * the reference effect writes {@code variable.emitter_age} in one component and
	 * {@code v.particle_age} in another. Without this they would be two separate variables.
	 */
	private static String canonical(String name) {
		String lower = name.toLowerCase(Locale.ROOT);

		if (lower.startsWith("v."))
			return "variable." + lower.substring(2);

		if (lower.startsWith("q."))
			return "query." + lower.substring(2);

		return lower;
	}

	static MolangValue constant(double value) {
		return new MolangValue() {
			@Override public double eval(MolangContext context) {
				return value;
			}

			@Override public boolean isConstant() {
				return true;
			}
		};
	}

	/** Collapses an operation whose operands are all constant into a single literal. */
	static MolangValue fold(MolangValue a, MolangValue result) {
		return a.isConstant() ? constant(result.eval(null)) : result;
	}

	static MolangValue fold(MolangValue a, MolangValue b, MolangValue result) {
		return a.isConstant() && b.isConstant() ? constant(result.eval(null)) : result;
	}

	static MolangValue fold(MolangValue a, MolangValue b, MolangValue c, MolangValue result) {
		return a.isConstant() && b.isConstant() && c.isConstant()
				? constant(result.eval(null)) : result;
	}

	// ------------------------------------------------------------ functions

	/** The {@code math.*} library, matching the set Snowstorm offers. */
	private static final class MolangFunctions {

		private static final Random RANDOM = new Random();

		static MolangValue build(String name, List<MolangValue> args, String source, int position) {
			return switch (name) {
				case "math.pi" -> constant(Math.PI);
				case "math.abs" -> unary(name, args, source, position, Math::abs);
				case "math.sin" -> unary(name, args, source, position, x -> Math.sin(Math.toRadians(x)));
				case "math.cos" -> unary(name, args, source, position, x -> Math.cos(Math.toRadians(x)));
				case "math.asin" -> unary(name, args, source, position, x -> Math.toDegrees(Math.asin(x)));
				case "math.acos" -> unary(name, args, source, position, x -> Math.toDegrees(Math.acos(x)));
				case "math.atan" -> unary(name, args, source, position, x -> Math.toDegrees(Math.atan(x)));
				case "math.exp" -> unary(name, args, source, position, Math::exp);
				case "math.ln" -> unary(name, args, source, position, Math::log);
				case "math.sqrt" -> unary(name, args, source, position, Math::sqrt);
				case "math.ceil" -> unary(name, args, source, position, Math::ceil);
				case "math.floor" -> unary(name, args, source, position, Math::floor);
				case "math.round" -> unary(name, args, source, position, x -> (double) Math.round(x));
				case "math.trunc" -> unary(name, args, source, position, x -> (double) (long) x);
				case "math.hermite_blend" -> unary(name, args, source, position,
						t -> 3 * t * t - 2 * t * t * t);
				case "math.min_angle" -> unary(name, args, source, position, MolangFunctions::wrapAngle);
				case "math.atan2" -> binary(name, args, source, position,
						(y, x) -> Math.toDegrees(Math.atan2(y, x)));
				case "math.mod" -> binary(name, args, source, position, (a, b) -> b == 0 ? 0 : a % b);
				case "math.pow" -> binary(name, args, source, position, Math::pow);
				case "math.min" -> binary(name, args, source, position, Math::min);
				case "math.max" -> binary(name, args, source, position, Math::max);
				case "math.clamp" -> {
					require(name, args, 3, source, position);

					MolangValue value = args.get(0);
					MolangValue low = args.get(1);
					MolangValue high = args.get(2);

					yield fold(value, low, high, context -> Math.max(low.eval(context),
							Math.min(high.eval(context), value.eval(context))));
				}
				case "math.lerp" -> {
					require(name, args, 3, source, position);

					MolangValue from = args.get(0);
					MolangValue to = args.get(1);
					MolangValue factor = args.get(2);

					yield fold(from, to, factor, context -> {
						double start = from.eval(context);

						return start + (to.eval(context) - start) * factor.eval(context);
					});
				}
				case "math.lerprotate" -> {
					require(name, args, 3, source, position);

					MolangValue from = args.get(0);
					MolangValue to = args.get(1);
					MolangValue factor = args.get(2);

					yield fold(from, to, factor, context -> {
						double start = from.eval(context);

						// Take the short way round the circle, as Bedrock does.
						return start + wrapAngle(to.eval(context) - start) * factor.eval(context);
					});
				}
				// Randoms are never folded: Bedrock re-rolls them on every evaluation, and the
				// engine relies on that to freeze spawn-time values itself.
				case "math.random" -> random(args, false);
				case "math.random_integer" -> random(args, true);
				case "math.die_roll" -> dieRoll(name, args, source, position, false);
				case "math.die_roll_integer" -> dieRoll(name, args, source, position, true);
				default -> throw new MolangSyntaxException(source, position,
						"unknown function '" + name + "'");
			};
		}

		/** Wraps an angle in degrees into {@code [-180, 180]}. */
		private static double wrapAngle(double angleDegrees) {
			double wrapped = (angleDegrees + 180) % 360;

			if (wrapped < 0)
				wrapped += 360;

			return wrapped - 180;
		}

		private static MolangValue random(List<MolangValue> args, boolean integer) {
			MolangValue low = args.size() >= 2 ? args.get(0) : constant(0);
			MolangValue high = args.size() >= 2 ? args.get(1)
					: args.size() == 1 ? args.get(0) : constant(1);
			MolangValue seed = args.size() >= 3 ? args.get(2) : null;

			// A seeded call (rare - 3-argument math.random) gets its own Random, compiled once and
			// reseeded on every evaluation rather than reallocated: setSeed(x) puts the generator in
			// exactly the same state a fresh `new Random(x)` would, without an eval() that allocates.
			Random seeded = seed != null ? new Random() : null;

			return context -> {
				double from = low.eval(context);
				double to = high.eval(context);
				double roll;

				if (seed == null) {
					roll = RANDOM.nextDouble();
				} else {
					seeded.setSeed((long) seed.eval(context));
					roll = seeded.nextDouble();
				}

				return integer ? Math.floor(from + roll * (Math.floor(to) - Math.floor(from) + 1))
						: from + roll * (to - from);
			};
		}

		private static MolangValue dieRoll(String name, List<MolangValue> args, String source,
				int position, boolean integer) {
			require(name, args, 3, source, position);

			MolangValue count = args.get(0);
			MolangValue low = args.get(1);
			MolangValue high = args.get(2);

			return context -> {
				double from = low.eval(context);
				double to = high.eval(context);
				int rolls = (int) count.eval(context);
				double total = 0;

				for (int i = 0; i < rolls; i++) {
					double roll = RANDOM.nextDouble();

					total += integer
							? Math.floor(from + roll * (Math.floor(to) - Math.floor(from) + 1))
							: from + roll * (to - from);
				}

				return total;
			};
		}

		private static MolangValue unary(String name, List<MolangValue> args, String source,
				int position, java.util.function.DoubleUnaryOperator operator) {
			require(name, args, 1, source, position);

			MolangValue operand = args.get(0);

			return fold(operand, context -> operator.applyAsDouble(operand.eval(context)));
		}

		private static MolangValue binary(String name, List<MolangValue> args, String source,
				int position, java.util.function.DoubleBinaryOperator operator) {
			require(name, args, 2, source, position);

			MolangValue left = args.get(0);
			MolangValue right = args.get(1);

			return fold(left, right,
					context -> operator.applyAsDouble(left.eval(context), right.eval(context)));
		}

		private static void require(String name, List<MolangValue> args, int arity, String source,
				int position) {
			if (args.size() != arity)
				throw new MolangSyntaxException(source, position,
						name + " takes " + arity + " argument(s), found " + args.size());
		}
	}
}
