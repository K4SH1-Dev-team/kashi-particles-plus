package net.kashi.particles.runtime;

import com.mojang.blaze3d.vertex.VertexConsumer;

import net.minecraft.client.particle.SingleQuadParticle;
import net.minecraft.client.renderer.SubmitNodeCollector;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.client.renderer.state.level.QuadParticleRenderState;

import org.joml.Quaternionf;
import org.joml.Vector3f;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

/**
 * The NeoForge 26.2 replacement for what {@code KashiRenderType} used to build directly - see the
 * 26.1.2 version of this file for the shared background (why this class exists at all: independent
 * width/height, which vanilla's own square-{@code scale} storage cannot carry).
 *
 * <p>26.2's own particle render-state API is genuinely different from 26.1.2's, not just renamed -
 * confirmed against the real 26.2 source, not assumed from 26.1.2 (that assumption would have been
 * wrong: {@code QuadParticleRenderState} dropped the whole {@code SubmitNodeCollector
 * .ParticleGroupRenderer}/{@code PreparedBuffers}/{@code RenderPass} indirection 26.1.2 needed, in
 * favour of a plain {@code buildLayer(Layer, VertexConsumer)} the engine calls directly - simpler,
 * and much closer to how 1.21.1/1.21.8 worked. The real constraint this file has to work around is
 * different too: {@code OrderedSubmitNodeCollector.submitQuadParticleGroup} takes the CONCRETE
 * {@code QuadParticleRenderState} type, not an interface - so unlike 26.1.2, this class cannot be a
 * free-standing implementation of some render-state interface. It has to actually extend {@code
 * QuadParticleRenderState}.
 *
 * <p>Every method that matters here is overridden with an entirely independent implementation,
 * deliberately never calling into the superclass's own storage: the inherited {@code add(...)}
 * only ever stores one {@code scale} float, so calling it would silently lose the non-square size
 * this class exists to preserve. The superclass's own (private) storage is simply left empty and
 * unused - inheritance here is purely to satisfy {@code submitQuadParticleGroup}'s type, not to
 * reuse behaviour.
 */
public final class KashiParticleRenderState extends QuadParticleRenderState {

	/** x, y, z, xRot, yRot, zRot, wRot, halfW, halfH, u0, u1, v0, v1 - 13 floats/particle. */
	private static final int FLOATS_PER_PARTICLE = 13;
	private static final int INTS_PER_PARTICLE = 2;

	private static final class Storage {
		private int capacity = 256;
		private float[] floats = new float[256 * FLOATS_PER_PARTICLE];
		private int[] ints = new int[256 * INTS_PER_PARTICLE];
		private int count;

		void add(float x, float y, float z, float xRot, float yRot, float zRot, float wRot,
				float halfW, float halfH, float u0, float u1, float v0, float v1,
				int color, int light) {
			if (this.count >= this.capacity)
				grow();

			int fi = this.count * FLOATS_PER_PARTICLE;
			this.floats[fi] = x;
			this.floats[fi + 1] = y;
			this.floats[fi + 2] = z;
			this.floats[fi + 3] = xRot;
			this.floats[fi + 4] = yRot;
			this.floats[fi + 5] = zRot;
			this.floats[fi + 6] = wRot;
			this.floats[fi + 7] = halfW;
			this.floats[fi + 8] = halfH;
			this.floats[fi + 9] = u0;
			this.floats[fi + 10] = u1;
			this.floats[fi + 11] = v0;
			this.floats[fi + 12] = v1;

			int ii = this.count * INTS_PER_PARTICLE;
			this.ints[ii] = color;
			this.ints[ii + 1] = light;

			this.count++;
		}

		private void grow() {
			this.capacity *= 2;
			this.floats = java.util.Arrays.copyOf(this.floats, this.capacity * FLOATS_PER_PARTICLE);
			this.ints = java.util.Arrays.copyOf(this.ints, this.capacity * INTS_PER_PARTICLE);
		}

		void clear() {
			this.count = 0;
		}
	}

	private final Map<SingleQuadParticle.Layer, Storage> layers = new HashMap<>();
	private int particleCount;

	/** Called once per particle per frame, from {@link KashiParticle#extractQuad}. */
	public void add(SingleQuadParticle.Layer layer, float x, float y, float z,
			float xRot, float yRot, float zRot, float wRot, float halfW, float halfH,
			float u0, float u1, float v0, float v1, int color, int light) {
		this.layers.computeIfAbsent(layer, ignored -> new Storage())
				.add(x, y, z, xRot, yRot, zRot, wRot, halfW, halfH, u0, u1, v0, v1, color, light);
		this.particleCount++;
	}

	@Override
	public void clear() {
		super.clear(); // no-op on the unused superclass storage, but keeps its state consistent
		this.layers.values().forEach(Storage::clear);
		this.particleCount = 0;
	}

	@Override
	public boolean isEmpty() {
		return this.particleCount == 0;
	}

	@Override
	public Set<SingleQuadParticle.Layer> layers() {
		return this.layers.keySet();
	}

	@Override
	public void buildLayer(SingleQuadParticle.Layer layer, VertexConsumer builder) {
		Storage storage = this.layers.get(layer);
		if (storage == null)
			return;

		for (int i = 0; i < storage.count; i++) {
			int fi = i * FLOATS_PER_PARTICLE;
			int ii = i * INTS_PER_PARTICLE;

			renderRotatedQuad(builder,
					storage.floats[fi], storage.floats[fi + 1], storage.floats[fi + 2],
					storage.floats[fi + 3], storage.floats[fi + 4], storage.floats[fi + 5], storage.floats[fi + 6],
					storage.floats[fi + 7], storage.floats[fi + 8],
					storage.floats[fi + 9], storage.floats[fi + 10], storage.floats[fi + 11], storage.floats[fi + 12],
					storage.ints[ii], storage.ints[ii + 1]);
		}
	}

	/**
	 * Not an override: the superclass's own {@code renderRotatedQuad} takes one {@code scale}, not
	 * two independent half-sizes, so this is a same-named replacement rather than a specialisation
	 * - {@link #buildLayer} above calls this one, never the inherited one.
	 */
	private static void renderRotatedQuad(VertexConsumer builder, float x, float y, float z,
			float xRot, float yRot, float zRot, float wRot, float halfW, float halfH,
			float u0, float u1, float v0, float v1, int color, int light) {
		Quaternionf rotation = new Quaternionf(xRot, yRot, zRot, wRot);

		renderVertex(builder, rotation, x, y, z, halfW, -halfH, u1, v1, color, light);
		renderVertex(builder, rotation, x, y, z, halfW, halfH, u1, v0, color, light);
		renderVertex(builder, rotation, x, y, z, -halfW, halfH, u0, v0, color, light);
		renderVertex(builder, rotation, x, y, z, -halfW, -halfH, u0, v1, color, light);
	}

	private static void renderVertex(VertexConsumer builder, Quaternionf rotation, float x, float y, float z,
			float ox, float oy, float u, float v, int color, int light) {
		Vector3f corner = new Vector3f(ox, oy, 0).rotate(rotation).add(x, y, z);

		builder.addVertex(corner.x(), corner.y(), corner.z()).setUv(u, v).setColor(color).setLight(light);
	}

	@Override
	public void submit(SubmitNodeCollector submitNodeCollector, CameraRenderState camera) {
		// Reimplements the inherited submit() rather than relying on it: that one checks the
		// superclass's own particleCount, which stays 0 forever here (see the class javadoc).
		if (!isEmpty())
			submitNodeCollector.submitQuadParticleGroup(this);
	}
}
