package net.kashi.particles.core;

/**
 * Samples a Bedrock curve, the thing behind Snowstorm's "Variables &amp; Curves" tab.
 *
 * <p>A curve turns one MoLang input into a {@code variable.*} an effect can read anywhere else, so
 * getting the sampling wrong does not fail loudly â€” it quietly returns the wrong number, and an
 * effect that drives its size from a curve simply vanishes. The maths here therefore follows
 * Wintersky's {@code calculateCurve} exactly rather than a plausible reading of the docs.
 *
 * <p>The input is normalised as {@code position = input / horizontal_range} and clamped to 0..1;
 * beyond the ends a curve holds its endpoint value.
 */
public final class CurveSampler {

	private CurveSampler() {
	}

	/** The four curve shapes Snowstorm can export. */
	public enum Type { LINEAR, CATMULL_ROM, BEZIER, BEZIER_CHAIN }

	/**
	 * @param t     the already-normalised input, 0..1 (values outside are clamped)
	 * @param nodes the curve's node values, in order
	 */
	public static double sample(Type type, double t, double[] nodes) {
		if (nodes.length == 0)
			return 0;

		if (nodes.length == 1)
			return nodes[0];

		double clamped = t < 0 ? 0 : Math.min(t, 1);

		return switch (type) {
			case LINEAR -> linear(clamped, nodes);
			case CATMULL_ROM -> catmullRom(clamped, nodes);
			case BEZIER -> bezier(clamped, nodes);
			// A chain is sampled through its own overload; reaching here means it had no key
			// frames, so there is nothing to interpolate between.
			case BEZIER_CHAIN -> nodes[0];
		};
	}

	private static double linear(double t, double[] nodes) {
		double position = t * (nodes.length - 1);
		int index = (int) Math.floor(position);

		if (index >= nodes.length - 1)
			return nodes[nodes.length - 1];

		return nodes[index] + (nodes[index + 1] - nodes[index]) * (position - index);
	}

	/**
	 * Uniform Catmull-Rom, as THREE.SplineCurve computes it for Wintersky.
	 *
	 * <p>The first and last nodes are <b>tangent handles, not points on the curve</b>: the visible
	 * curve runs from {@code nodes[1]} to {@code nodes[n - 2]}. Sampling all n nodes instead would
	 * shift every value along the curve, which is the subtle failure this method exists to avoid.
	 */
	private static double catmullRom(double t, double[] nodes) {
		int n = nodes.length;

		// Fewer than four nodes leaves no interior span; there is nothing to do but interpolate
		// what is there.
		if (n < 4)
			return linear(t, nodes);

		double position = t * (n - 3) + 1;
		int index = (int) Math.floor(position);

		if (index > n - 1)
			index = n - 1;

		double weight = position - index;

		double p0 = nodes[index == 0 ? 0 : index - 1];
		double p1 = nodes[index];
		double p2 = nodes[index > n - 2 ? n - 1 : index + 1];
		double p3 = nodes[index > n - 3 ? n - 1 : index + 2];

		return catmullRomSegment(weight, p0, p1, p2, p3);
	}

	private static double catmullRomSegment(double t, double p0, double p1, double p2, double p3) {
		double v0 = (p2 - p0) * 0.5;
		double v1 = (p3 - p1) * 0.5;
		double t2 = t * t;
		double t3 = t * t2;

		return (2 * p1 - 2 * p2 + v0 + v1) * t3
				+ (-3 * p1 + 3 * p2 - 2 * v0 - v1) * t2
				+ v0 * t + p1;
	}

	/** A plain cubic Bezier over exactly four nodes: two endpoints and two control values. */
	private static double bezier(double t, double[] nodes) {
		if (nodes.length < 4)
			return linear(t, nodes);

		double u = 1 - t;

		return u * u * u * nodes[0]
				+ 3 * u * u * t * nodes[1]
				+ 3 * u * t * t * nodes[2]
				+ t * t * t * nodes[3];
	}

	// ----------------------------------------------------------- bezier chain

	/**
	 * One key frame of a {@code bezier_chain}.
	 *
	 * <p>A key can be a corner: {@code leftValue} is approached from before it and
	 * {@code rightValue} leaves it, and the two need not agree.
	 */
	public record ChainKey(double time, double leftValue, double rightValue,
			double leftSlope, double rightSlope) {}

	/**
	 * Samples a {@code bezier_chain} at the normalised input {@code t}.
	 *
	 * <p>Each span between consecutive keys is a cubic Hermite segment, its control points placed a
	 * third of the span away along the keys' slopes â€” the standard reading of Bedrock's
	 * value/slope pairs. Keys must be sorted by {@link ChainKey#time}.
	 */
	public static double sampleChain(double t, ChainKey[] keys) {
		if (keys.length == 0)
			return 0;

		if (keys.length == 1)
			return keys[0].rightValue();

		if (t <= keys[0].time())
			return keys[0].rightValue();

		if (t >= keys[keys.length - 1].time())
			return keys[keys.length - 1].leftValue();

		int index = 0;

		while (index < keys.length - 2 && keys[index + 1].time() <= t)
			index++;

		ChainKey from = keys[index];
		ChainKey to = keys[index + 1];
		double span = to.time() - from.time();

		if (span <= 0)
			return to.leftValue();

		double local = (t - from.time()) / span;
		double third = span / 3;

		return bezier(local, new double[] {
				from.rightValue(),
				from.rightValue() + from.rightSlope() * third,
				to.leftValue() - to.leftSlope() * third,
				to.leftValue() });
	}
}
