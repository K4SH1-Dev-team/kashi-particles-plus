package net.kashi.particles.core;

import com.google.gson.JsonParser;

import net.kashi.particles.core.molang.MolangCompiler;
import net.kashi.particles.core.molang.MolangContext;
import net.kashi.particles.core.molang.MolangContext.Var;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Diagnostic CLI: parses one {@code .particle.json} the way the runtime does and reports what it
 * found, so a misbehaving effect can be inspected without launching Minecraft.
 *
 * <p>Reports the numbers that decide whether anything is visible at all — how many particles the
 * emitter will make, how long they live, and how big they are — because an effect that "does not
 * play" is usually one whose own values evaluate to zero.
 *
 * <p>Run via {@code tools/inspect-particle.ps1 <file>}.
 */
public final class ParticleInspector {

	public static void main(String[] args) throws Exception {
		if (args.length < 1) {
			System.out.println("usage: ParticleInspector <file.particle.json>");
			System.exit(2);
		}

		Path file = Path.of(args[0]);
		KashiParticleDefinition definition;

		try {
			definition = KashiParticleDefinition.parse(
					JsonParser.parseString(Files.readString(file)).getAsJsonObject());
		} catch (KashiParticleParseException rejected) {
			System.out.println("REJECTED: " + rejected.getMessage());
			System.exit(1);
			return;
		}

		System.out.println("identifier : " + definition.identifier());
		System.out.println("material   : " + definition.render().material() + "  -> " + definition.render().blend());
		System.out.println("texture    : " + definition.render().texture());
		System.out.println("shape      : " + definition.shape().getClass().getSimpleName());
		System.out.println("lit by world: " + definition.litByWorld());

		MolangCompiler compiler = new MolangCompiler();
		MolangContext context = compiler.newContext();

		// A fresh emitter at t=0 with mid-range randoms: representative of the first particle.
		context.set(Var.EMITTER_AGE, 0);
		context.set(Var.PARTICLE_AGE, 0);
		context.set(Var.PARTICLE_RANDOM_1, 0.5);
		context.set(Var.PARTICLE_RANDOM_2, 0.5);
		context.set(Var.PARTICLE_RANDOM_3, 0.5);
		context.set(Var.PARTICLE_RANDOM_4, 0.5);

		System.out.println();
		report("emitter rate", switch (definition.rate()) {
			case KashiParticleDefinition.EmitterRate.Steady steady ->
					eval(compiler, context, steady.spawnRate()) + " /s, max alive "
							+ eval(compiler, context, steady.maxParticles());
			case KashiParticleDefinition.EmitterRate.Instant instant ->
					eval(compiler, context, instant.numParticles()) + " at once";
			case KashiParticleDefinition.EmitterRate.Manual manual ->
					"manual, max " + eval(compiler, context, manual.maxParticles());
		});

		report("emitter life", switch (definition.lifetime()) {
			case KashiParticleDefinition.EmitterLifetime.Once once ->
					eval(compiler, context, once.activeTime()) + "s";
			case KashiParticleDefinition.EmitterLifetime.Looping looping ->
					"loop " + eval(compiler, context, looping.activeTime()) + "s on / "
							+ eval(compiler, context, looping.sleepTime()) + "s off";
			case KashiParticleDefinition.EmitterLifetime.Expression expression -> "expression-driven";
		});

		double life = eval(compiler, context, definition.particleLifetime().maxLifetime());
		report("particle life", life + "s");

		double width = eval(compiler, context, definition.appearance().size().x());
		double height = eval(compiler, context, definition.appearance().size().y());
		report("particle size", width + " x " + height + " (half-extents)");

		simulateLife(definition, compiler, context, life);

		// The reasons an effect ends up invisible are shared with the batch validator, so they live
		// in one place rather than drifting apart between the two tools.
		List<ParticleDiagnostics.Diagnostic> findings = ParticleDiagnostics.analyse(definition);

		if (!findings.isEmpty()) {
			System.out.println();
			System.out.println("findings:");

			findings.forEach(finding -> System.out.println("  !! " + finding));
		}

		if (!definition.unsupported().isEmpty()) {
			System.out.println();
			System.out.println("unsupported components:");

			for (KashiParticleDefinition.Unsupported entry : definition.unsupported())
				System.out.println("  - " + entry.component() + ": " + entry.impact());
		}

		System.out.println();
		System.out.println("OK - the runtime can load this effect.");
	}

	/**
	 * Walks one particle through its life, tick by tick, reporting what would actually be drawn.
	 *
	 * <p>This is where "it plays in Snowstorm but not in game" usually gets answered: an alpha that
	 * never rises above zero, or flipbook frames that run past the end of the texture.
	 */
	private static void simulateLife(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context, double life) {
		System.out.println();
		System.out.println("life simulation (tick: alpha, flipbook frame, u range)");

		KashiParticleDefinition.Uv sheet = definition.appearance().uv();
		KashiParticleDefinition.Flipbook flipbook = sheet.flipbook();
		double texW = sheet.textureWidth();

		int ticks = Math.max(1, (int) Math.ceil(life * 20));
		double peakAlpha = 0;
		boolean offTexture = false;

		context.set(Var.PARTICLE_LIFETIME, life);

		for (int tick = 0; tick <= ticks; tick++) {
			double age = tick / 20.0;
			context.set(Var.PARTICLE_AGE, age);

			double alpha = alphaAt(definition, compiler, context);
			peakAlpha = Math.max(peakAlpha, alpha);

			String frameInfo = "-";

			if (flipbook != null) {
				double fps = flipbook.stretchToLifetime()
						? (life > 0 ? flipbook.maxFrame() / life : 0)
						: eval(compiler, context, flipbook.fps());
				double animDuration = fps > 0 ? flipbook.maxFrame() / fps : life;
				double loopTime = flipbook.loop()
						? (animDuration > 0 ? age % animDuration : 0)
						: Math.min(age, animDuration);
				int frame = (int) Math.floor(loopTime * fps);

				frame = Math.max(0, Math.min(frame, (int) flipbook.maxFrame() - 1));

				double u0 = (eval(compiler, context, flipbook.baseUv().x())
						+ eval(compiler, context, flipbook.stepUv().x()) * frame) / texW;
				double u1 = u0 + eval(compiler, context, flipbook.sizeUv().x()) / texW;

				if (u1 > 1.0001) {
					offTexture = true;
					frameInfo = String.format("%d  u %.2f..%.2f  << PAST END OF TEXTURE", frame, u0, u1);
				} else {
					frameInfo = String.format("%d  u %.2f..%.2f", frame, u0, u1);
				}
			}

			System.out.printf("  t%-3d  alpha %.2f   frame %s%n", tick, alpha, frameInfo);
		}

		if (peakAlpha > 0.01 && offTexture)
			System.out.println();
	}

	private static double alphaAt(KashiParticleDefinition definition, MolangCompiler compiler,
			MolangContext context) {
		return ParticleDiagnostics.alphaAt(definition, compiler, context);
	}

	private static double eval(MolangCompiler compiler, MolangContext context, MolangExpr expr) {
		return expr.compile(compiler).eval(context);
	}

	private static void report(String label, Object value) {
		System.out.printf("%-14s: %s%n", label, value);
	}
}
