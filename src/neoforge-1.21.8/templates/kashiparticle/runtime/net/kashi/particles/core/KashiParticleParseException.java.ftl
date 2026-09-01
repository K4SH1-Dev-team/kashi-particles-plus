package net.kashi.particles.core;

/**
 * Thrown when a {@code .particle.json} cannot be understood as a Bedrock particle effect.
 *
 * <p>The message always carries the JSON path of the offending node so the import wizard
 * can tell the user exactly which component is at fault.
 */
public class KashiParticleParseException extends RuntimeException {

	public KashiParticleParseException(String path, String message) {
		super(path.isEmpty() ? message : path + ": " + message);
	}

	public KashiParticleParseException(String path, String message, Throwable cause) {
		super(path.isEmpty() ? message : path + ": " + message, cause);
	}
}
