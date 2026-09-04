package net.kashi.particles.runtime;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Records what each effect actually did when it was fired, so "nothing appeared" becomes a number.
 *
 * <p>An effect can come out invisible for a dozen reasons that all look identical in-game: it never
 * spawned, it spawned and was never drawn, it was drawn at zero size, or drawn fully transparent.
 * Those are four different bugs and guessing between them from the outside is hopeless, so the
 * runtime counts them as it goes.
 *
 * <p>Client-side and diagnostic only. Nothing here changes what is rendered.
 */
public final class KashiDiagnostics {

	private KashiDiagnostics() {
	}

	/** What one effect did since the player logged in. */
	public static final class Record {

		int spawned;
		int drawn;
		float maxSize;
		float maxAlpha;

		/** Reads the story out of the counters, in the order the failures actually happen. */
		public String verdict() {
			if (this.spawned == 0)
				return "NEVER SPAWNED - the emitter produced no particles at all";

			if (this.drawn == 0)
				return "spawned " + this.spawned + " but NEVER DRAWN - culled, or dead before a frame";

			if (this.maxSize <= 0)
				return "drawn " + this.drawn + "x at ZERO SIZE";

			if (this.maxAlpha <= 0.02f)
				return "drawn " + this.drawn + "x but FULLY TRANSPARENT";

			return String.format("ok - %d spawned, %d draws, size up to %.2f, alpha up to %.2f",
					this.spawned, this.drawn, this.maxSize, this.maxAlpha);
		}

		public boolean looksWrong() {
			return this.spawned == 0 || this.drawn == 0 || this.maxSize <= 0 || this.maxAlpha <= 0.02f;
		}
	}

	private static final Map<String, Record> RECORDS = new ConcurrentHashMap<>();

	static void spawned(String effect) {
		RECORDS.computeIfAbsent(effect, key -> new Record()).spawned++;
	}

	static void drawn(String effect, float size, float alpha) {
		Record record = RECORDS.computeIfAbsent(effect, key -> new Record());

		record.drawn++;
		record.maxSize = Math.max(record.maxSize, size);
		record.maxAlpha = Math.max(record.maxAlpha, alpha);
	}

	public static Map<String, Record> records() {
		return RECORDS;
	}

	public static void clear() {
		RECORDS.clear();
	}
}
