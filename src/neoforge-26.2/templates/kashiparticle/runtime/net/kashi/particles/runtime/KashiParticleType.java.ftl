package net.kashi.particles.runtime;

import com.mojang.serialization.MapCodec;

import net.minecraft.core.particles.ParticleType;
import net.minecraft.network.RegistryFriendlyByteBuf;
import net.minecraft.network.codec.StreamCodec;

/**
 * The single {@link ParticleType} under which all KASHI effects are spawned. Which effect actually
 * plays is decided by the {@link KashiParticleOptions#effectId()} carried at spawn time.
 */
public class KashiParticleType extends ParticleType<KashiParticleOptions> {

	public KashiParticleType() {
		// overrideLimiter: always create the (invisible) emitter driver, regardless of the
		// client's particle-visibility distance or "Particles" video setting.
		//
		// This costs nothing: the emitter itself never renders (see KashiEmitterParticle), and its
		// visible children are added straight into the vanilla particle engine rather than through
		// this type's own spawn path, so they were never subject to this limiter in the first
		// place. Leaving it false meant an effect fired more than ~15-30 blocks away (exact
		// distance depends on angle - confirmed by decompiling LevelRenderer.addParticle, which
		// reads ParticleType.getOverrideLimiter()) silently never got its emitter created at all:
		// no spawn, no error, indistinguishable from a broken effect. That is the wrong default
		// for content a mod author deliberately imported and wired up to play.
		super(true);
	}

	@Override
	public MapCodec<KashiParticleOptions> codec() {
		return KashiParticleOptions.CODEC;
	}

	@Override
	public StreamCodec<? super RegistryFriendlyByteBuf, KashiParticleOptions> streamCodec() {
		return KashiParticleOptions.STREAM_CODEC;
	}
}
