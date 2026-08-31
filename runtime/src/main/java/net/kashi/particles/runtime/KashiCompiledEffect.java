package net.kashi.particles.runtime;

import net.kashi.particles.core.KashiParticleDefinition;
import net.kashi.particles.core.KashiParticleDefinition.BlendMode;
import net.kashi.particles.core.MolangExpr;
import net.kashi.particles.core.molang.MolangCompiler;
import net.kashi.particles.core.molang.MolangContext;
import net.kashi.particles.core.molang.MolangValue;

import net.minecraft.resources.ResourceLocation;

/**
 * A {@link KashiParticleDefinition} with every MoLang expression compiled and a resolved texture
 * location, ready to drive live particles.
 *
 * <p>All expressions are compiled by one shared {@link MolangCompiler} so they agree on where each
 * custom {@code variable.*} lives. Compilation happens once, at registration; if any expression is
 * malformed it fails here with a clear message rather than mid-render.
 *
 * <p>Instances are immutable and shared by every particle of the effect. Per-particle state lives
 * in {@link MolangContext} objects handed out by {@link #newContext()}.
 */
public final class KashiCompiledEffect {

	private final KashiParticleDefinition definition;
	private final MolangCompiler compiler;
	private final ResourceLocation texture;

	/** One curve, ready to evaluate: its slot resolved and its expressions compiled. */
	private record CompiledCurve(int slot, KashiParticleDefinition.Curve curve,
			MolangValue input, MolangValue range) {}

	private CompiledCurve[] curves = new CompiledCurve[0];

	private KashiCompiledEffect(KashiParticleDefinition definition, MolangCompiler compiler,
			ResourceLocation texture) {
		this.definition = definition;
		this.compiler = compiler;
		this.texture = texture;
	}

	/**
	 * Compiles a parsed definition.
	 *
	 * @param texture where the effect's PNG lives in the mod's assets; the Bedrock
	 *                {@code basic_render_parameters.texture} path is not reused directly because
	 *                the import step copies the texture to a mod-owned location.
	 */
	public static KashiCompiledEffect compile(KashiParticleDefinition definition, ResourceLocation texture) {
		MolangCompiler compiler = new MolangCompiler();
		KashiCompiledEffect effect = new KashiCompiledEffect(definition, compiler, texture);

		// Touch every expression now so a syntax error surfaces at registration.
		effect.compileEverything();

		return effect;
	}

	public KashiParticleDefinition definition() {
		return this.definition;
	}

	public ResourceLocation texture() {
		return this.texture;
	}

	public BlendMode blend() {
		return this.definition.render().blend();
	}

	public MolangContext newContext() {
		return this.compiler.newContext();
	}

	/** Compiles one expression against this effect's shared compiler (cached by the expr). */
	public MolangValue compile(MolangExpr expr) {
		return expr.compile(this.compiler);
	}

	/**
	 * Recomputes every curve into {@code context}, so the expressions evaluated next see current
	 * values.
	 *
	 * <p>Call this before reading anything from a context that has just had its clock advanced —
	 * on the emitter each emitter tick, on a particle each particle tick and each frame. A curve's
	 * input is evaluated in the context it is being applied to, which is what lets the same effect
	 * hold one curve driven by {@code v.emitter_age} and another by {@code v.particle_age}.
	 */
	public void applyCurves(MolangContext context) {
		for (CompiledCurve compiled : this.curves) {
			double range = compiled.range().eval(context);
			// Wintersky reads a zero or non-finite range as "always at the start of the curve"
			// rather than as an error.
			double position = range == 0 ? 0 : compiled.input().eval(context) / range;

			if (!Double.isFinite(position))
				position = 0;

			KashiParticleDefinition.Curve curve = compiled.curve();
			double value = curve.chain() != null
					? net.kashi.particles.core.CurveSampler.sampleChain(position, curve.chain())
					: net.kashi.particles.core.CurveSampler.sample(curve.type(), position, curve.nodes());

			context.setVariable(compiled.slot(), value);
		}
	}

	public boolean hasCurves() {
		return this.curves.length > 0;
	}

	private void compileEverything() {
		KashiParticleDefinition d = this.definition;

		// Curves first: reserving their slots before anything else compiles keeps a curve that no
		// expression happens to read from being allocated after the first context was handed out.
		this.curves = d.curves().stream()
				.map(curve -> new CompiledCurve(this.compiler.slotOf(curve.variable()), curve,
						compile(curve.input()), compile(curve.horizontalRange())))
				.toArray(CompiledCurve[]::new);

		compileShape(d.shape());
		compileRate(d.rate());
		compileLifetime(d.lifetime());
		compile(d.particleLifetime().maxLifetime());
		compile(d.particleLifetime().expiration());

		if (d.initialSpin() != null) {
			compile(d.initialSpin().rotation());
			compile(d.initialSpin().rotationRate());
		}

		switch (d.initialSpeed()) {
			case KashiParticleDefinition.InitialSpeed.AlongDirection along -> compile(along.speed());
			case KashiParticleDefinition.InitialSpeed.Velocity explicit -> compileVec3(explicit.velocity());
			case null -> { }
		}

		if (d.motion() != null) {
			compileVec3(d.motion().linearAcceleration());
			compile(d.motion().linearDrag());
			compile(d.motion().rotationAcceleration());
			compile(d.motion().rotationDrag());
		}

		compileVec2(d.appearance().size());

		if (d.appearance().uv().isAnimated())
			compile(d.appearance().uv().flipbook().fps());

		if (d.tinting() != null && d.tinting().interpolant() != null)
			compile(d.tinting().interpolant());

		if (d.emitterInit() != null) {
			compile(d.emitterInit().creation());
			compile(d.emitterInit().perUpdate());
		}

		if (d.particleInit() != null) {
			compile(d.particleInit().perUpdate());
			compile(d.particleInit().perRender());
		}

		if (d.collision() != null)
			compile(d.collision().enabled());

		if (d.motionParametric() != null) {
			compileVec3(d.motionParametric().relativePosition());
			compileVec3(d.motionParametric().direction());
			compile(d.motionParametric().rotation());
		}
	}

	private void compileShape(KashiParticleDefinition.EmitterShape shape) {
		compileVec3(shape.offset());

		switch (shape) {
			case KashiParticleDefinition.EmitterShape.Sphere sphere -> compile(sphere.radius());
			case KashiParticleDefinition.EmitterShape.Box box -> compileVec3(box.halfDimensions());
			case KashiParticleDefinition.EmitterShape.Disc disc -> {
				compileVec3(disc.planeNormal());
				compile(disc.radius());
			}
			default -> { }
		}
	}

	private void compileRate(KashiParticleDefinition.EmitterRate rate) {
		switch (rate) {
			case KashiParticleDefinition.EmitterRate.Steady steady -> {
				compile(steady.spawnRate());
				compile(steady.maxParticles());
			}
			case KashiParticleDefinition.EmitterRate.Instant instant -> compile(instant.numParticles());
			case KashiParticleDefinition.EmitterRate.Manual manual -> compile(manual.maxParticles());
		}
	}

	private void compileLifetime(KashiParticleDefinition.EmitterLifetime lifetime) {
		switch (lifetime) {
			case KashiParticleDefinition.EmitterLifetime.Once once -> compile(once.activeTime());
			case KashiParticleDefinition.EmitterLifetime.Looping looping -> {
				compile(looping.activeTime());
				compile(looping.sleepTime());
			}
			case KashiParticleDefinition.EmitterLifetime.Expression expression -> {
				compile(expression.activation());
				compile(expression.expiration());
			}
		}
	}

	private void compileVec2(KashiParticleDefinition.Vec2Expr vec) {
		compile(vec.x());
		compile(vec.y());
	}

	private void compileVec3(KashiParticleDefinition.Vec3Expr vec) {
		compile(vec.x());
		compile(vec.y());
		compile(vec.z());
	}
}
