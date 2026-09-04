package net.kashi.particles.runtime;

import com.mojang.blaze3d.buffers.GpuBufferSlice;
import com.mojang.blaze3d.systems.RenderPass;
import com.mojang.blaze3d.systems.RenderSystem;
import com.mojang.blaze3d.vertex.BufferBuilder;
import com.mojang.blaze3d.vertex.ByteBufferBuilder;
import com.mojang.blaze3d.vertex.DefaultVertexFormat;
import com.mojang.blaze3d.vertex.MeshData;
import com.mojang.blaze3d.vertex.VertexConsumer;
import com.mojang.blaze3d.vertex.VertexFormat;

import net.minecraft.client.particle.SingleQuadParticle;
import net.minecraft.client.renderer.SubmitNodeCollector;
import net.minecraft.client.renderer.feature.ParticleFeatureRenderer;
import net.minecraft.client.renderer.state.level.CameraRenderState;
import net.minecraft.client.renderer.state.level.ParticleGroupRenderState;
import net.minecraft.client.renderer.state.level.QuadParticleRenderState;
import net.minecraft.client.renderer.texture.AbstractTexture;
import net.minecraft.client.renderer.texture.TextureManager;

import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector3f;
import org.joml.Vector4f;

import java.util.HashMap;
import java.util.Map;

/**
 * The NeoForge 26.1.2/26.2 replacement for what {@code KashiRenderType} used to build directly:
 * a per-frame batch of KASHI quads, grouped by {@link SingleQuadParticle.Layer} (texture + blend),
 * ready to hand the GPU a vertex buffer.
 *
 * <p>Reimplements {@code net.minecraft.client.renderer.state.level.QuadParticleRenderState}
 * almost exactly (same {@code PreparedBuffers}/{@code PreparedLayer} output types - required, since
 * {@link SubmitNodeCollector.ParticleGroupRenderer#prepare}/{@code render} are hard-typed to those,
 * not to any interface a mod could implement its own version of), with one real difference: vanilla
 * stores a single {@code scale} float per particle, so every quad it can extract is square. KASHI
 * particles have independently authored width and height (Bedrock's {@code particle_appearance
 * .size.x}/{@code .y}), so this stores {@code halfW}/{@code halfH} separately and multiplies each
 * into its own axis when a corner is expanded - the one place this class's geometry math diverges
 * from vanilla's {@code renderVertex}.
 *
 * <p>One instance is created once per {@link KashiParticleGroup} and reused every frame - the
 * engine clears it (via {@link #clear}) right before repopulating it, the same lifecycle vanilla's
 * own {@code QuadParticleRenderState} instances follow (see {@code ParticlesRenderState.reset()}).
 */
public final class KashiParticleRenderState implements ParticleGroupRenderState, SubmitNodeCollector.ParticleGroupRenderer {

	/** x, y, z, xRot, yRot, zRot, wRot, halfW, halfH, u0, u1, v0, v1 - 13 floats/particle. */
	private static final int FLOATS_PER_PARTICLE = 13;
	/** color, light - 2 ints/particle. */
	private static final int INTS_PER_PARTICLE = 2;

	/** One growable array pair per (texture, blend) layer, mirroring vanilla's own per-layer split. */
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
		this.layers.values().forEach(Storage::clear);
		this.particleCount = 0;
	}

	@Override
	public boolean isEmpty() {
		return this.particleCount == 0;
	}

	@Override
	public void submit(SubmitNodeCollector submitNodeCollector, CameraRenderState camera) {
		if (this.particleCount > 0)
			submitNodeCollector.submitParticleGroup(this);
	}

	/**
	 * Builds this frame's vertex buffer, one QUADS-mode {@link BufferBuilder} draw covering every
	 * layer whose {@link SingleQuadParticle.Layer#translucent()} matches {@code translucent} - same
	 * split vanilla's own two-pass (opaque then translucent) particle render does.
	 */
	@Override
	public QuadParticleRenderState.PreparedBuffers prepare(
			ParticleFeatureRenderer.ParticleBufferCache cachedBuffer, boolean translucent) {
		if (isEmpty())
			return null;

		int vertexCount = this.particleCount * 4;

		try (ByteBufferBuilder builder =
				ByteBufferBuilder.exactlySized(vertexCount * DefaultVertexFormat.PARTICLE.getVertexSize())) {
			BufferBuilder bufferBuilder = new BufferBuilder(builder, VertexFormat.Mode.QUADS, DefaultVertexFormat.PARTICLE);
			Map<SingleQuadParticle.Layer, QuadParticleRenderState.PreparedLayer> prepared = new HashMap<>();
			int offset = 0;

			for (Map.Entry<SingleQuadParticle.Layer, Storage> entry : this.layers.entrySet()) {
				if (entry.getKey().translucent() != translucent)
					continue;

				Storage storage = entry.getValue();

				for (int i = 0; i < storage.count; i++) {
					int fi = i * FLOATS_PER_PARTICLE;
					int ii = i * INTS_PER_PARTICLE;

					renderRotatedQuad(bufferBuilder,
							storage.floats[fi], storage.floats[fi + 1], storage.floats[fi + 2],
							storage.floats[fi + 3], storage.floats[fi + 4], storage.floats[fi + 5], storage.floats[fi + 6],
							storage.floats[fi + 7], storage.floats[fi + 8],
							storage.floats[fi + 9], storage.floats[fi + 10], storage.floats[fi + 11], storage.floats[fi + 12],
							storage.ints[ii], storage.ints[ii + 1]);
				}

				if (storage.count > 0)
					prepared.put(entry.getKey(), new QuadParticleRenderState.PreparedLayer(offset, storage.count * 6));

				offset += storage.count * 4;
			}

			MeshData mesh = bufferBuilder.build();
			if (mesh == null)
				return null;

			cachedBuffer.write(mesh.vertexBuffer());
			RenderSystem.getSequentialBuffer(VertexFormat.Mode.QUADS).getBuffer(mesh.drawState().indexCount());

			GpuBufferSlice dynamicTransforms = RenderSystem.getDynamicUniforms().writeTransform(
					RenderSystem.getModelViewMatrix(), new Vector4f(1, 1, 1, 1), new Vector3f(), new Matrix4f());

			return new QuadParticleRenderState.PreparedBuffers(mesh.drawState().indexCount(), dynamicTransforms, prepared);
		}
	}

	@Override
	public void render(QuadParticleRenderState.PreparedBuffers buffers,
			ParticleFeatureRenderer.ParticleBufferCache bufferCache, RenderPass renderPass,
			TextureManager textureManager) {
		RenderSystem.AutoStorageIndexBuffer indexBuffer = RenderSystem.getSequentialBuffer(VertexFormat.Mode.QUADS);
		renderPass.setVertexBuffer(0, bufferCache.get());
		renderPass.setIndexBuffer(indexBuffer.getBuffer(buffers.indexCount()), indexBuffer.type());
		renderPass.setUniform("DynamicTransforms", buffers.dynamicTransforms());

		for (Map.Entry<SingleQuadParticle.Layer, QuadParticleRenderState.PreparedLayer> entry
				: buffers.layers().entrySet()) {
			renderPass.setPipeline(entry.getKey().pipeline());
			AbstractTexture texture = textureManager.getTexture(entry.getKey().textureAtlasLocation());
			renderPass.bindTexture("Sampler0", texture.getTextureView(), texture.getSampler());
			renderPass.drawIndexed(entry.getValue().vertexOffset(), 0, entry.getValue().indexCount(), 1);
		}
	}

	/** The one place this class's math actually differs from vanilla's: two independent half-sizes. */
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
}
