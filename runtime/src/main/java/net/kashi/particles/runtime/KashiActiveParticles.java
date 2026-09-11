package net.kashi.particles.runtime;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.ClientPlayerNetworkEvent;

import net.minecraft.resources.ResourceLocation;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Every directly-spawned {@link KashiEmitterParticle} currently running on this client, keyed by
 * the {@code (effectId, entityId)} pair "Stop K4SH1 Particle" targets — see
 * {@code KashiParticleAPI#stopKashiParticle} for how a Stop is sent and
 * {@code KashiStopParticlesPayload} for what crosses the wire.
 *
 * <p>Only a directly-spawned emitter (the one {@link KashiParticleClient}'s provider constructs
 * straight from a spawn packet) registers here - an effect fired as another effect's own chained
 * event (see {@code KashiEventRunner}) never passes through {@code KashiParticleOptions} at all, so
 * it structurally has no {@code (effectId, entityId)} of its own to register under. That mirrors
 * what a pack author can actually target: a chained effect was never independently selectable from
 * a Blockly block, only ever a detail of the effect that triggers it.
 *
 * <p>{@code entityId} reuses {@code KashiParticleOptions.NO_ENTITY}, exactly like a spawn packet
 * does - a Stop naming no entity matches every no-owner instance of that effect (world/block
 * spawns), which is a direct and intended consequence of that sentinel being shared, not a special
 * case handled here.
 */
@EventBusSubscriber(modid = KashiParticlesRuntime.MODID, value = Dist.CLIENT, bus = EventBusSubscriber.Bus.GAME)
final class KashiActiveParticles {

	private record Key(ResourceLocation effectId, int entityId) {
	}

	private static final Map<Key, List<KashiEmitterParticle>> ACTIVE = new HashMap<>();

	private KashiActiveParticles() {
	}

	static void track(ResourceLocation effectId, int entityId, KashiEmitterParticle particle) {
		ACTIVE.computeIfAbsent(new Key(effectId, entityId), unused -> new ArrayList<>()).add(particle);
	}

	static void untrack(ResourceLocation effectId, int entityId, KashiEmitterParticle particle) {
		Key key = new Key(effectId, entityId);
		List<KashiEmitterParticle> tracked = ACTIVE.get(key);

		if (tracked == null)
			return;

		tracked.remove(particle);

		if (tracked.isEmpty())
			ACTIVE.remove(key);
	}

	/** Ends every currently-tracked instance matching {@code effectId} owned by {@code entityId}. */
	static void stopMatching(ResourceLocation effectId, int entityId) {
		List<KashiEmitterParticle> hit = ACTIVE.get(new Key(effectId, entityId));

		if (hit == null)
			return;

		// A copy: KashiEmitterParticle#remove() untracks itself, which would otherwise mutate this
		// same list mid-iteration.
		for (KashiEmitterParticle particle : List.copyOf(hit))
			particle.remove();
	}

	/**
	 * Drops everything this client was tracking, with no per-particle {@code remove()} call.
	 * Vanilla's own {@code ParticleEngine#clearParticles} (fired on level change and disconnect)
	 * never calls {@code remove()} on the particles it drops either - it just empties its own lists
	 * - so without this, an effect still running at that moment would leak its entry here forever:
	 * nothing ever ticks it again to expire naturally, and nothing else ever removes it.
	 */
	static void clear() {
		ACTIVE.clear();
	}

	@SubscribeEvent
	static void onLoggingOut(ClientPlayerNetworkEvent.LoggingOut event) {
		clear();
	}

	/** Fired on respawn and on every dimension change - the other path a tracked effect can outlive. */
	@SubscribeEvent
	static void onPlayerClone(ClientPlayerNetworkEvent.Clone event) {
		clear();
	}
}
