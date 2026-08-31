package net.kashi.particles.core;

import com.google.gson.JsonParser;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

/**
 * Runs the parser over a whole folder of {@code .particle.json} files and summarises what would
 * happen to each one at runtime.
 *
 * <p>Answers the question that matters before shipping a pack: which effects will not load at all,
 * and which will load but quietly lose behaviour. Rejections are listed individually because each
 * is an effect that simply will not play; warnings are aggregated by component because they repeat.
 *
 * <p>Run via {@code tools/validate-particles.ps1 <folder>}.
 */
public final class ParticleBatchValidator {

	public static void main(String[] args) throws IOException {
		if (args.length < 1) {
			System.out.println("usage: ParticleBatchValidator <folder>");
			System.exit(2);
		}

		List<Path> files = new ArrayList<>();

		try (Stream<Path> walk = Files.walk(Path.of(args[0]))) {
			walk.filter(Files::isRegularFile)
					.filter(path -> path.toString().endsWith(".json"))
					.sorted()
					.forEach(files::add);
		}

		Map<String, List<String>> rejections = new LinkedHashMap<>();
		Map<String, Integer> unsupported = new LinkedHashMap<>();
		Map<String, List<String>> findings = new LinkedHashMap<>();
		Map<String, List<String>> identifiers = new LinkedHashMap<>();
		int loaded = 0;
		int invisible = 0;

		for (Path file : files) {
			try {
				KashiParticleDefinition definition = KashiParticleDefinition.parse(
						JsonParser.parseString(Files.readString(file)).getAsJsonObject());

				loaded++;
				identifiers.computeIfAbsent(definition.identifier(), key -> new ArrayList<>())
						.add(file.getFileName().toString());

				for (KashiParticleDefinition.Unsupported entry : definition.unsupported())
					unsupported.merge(entry.component(), 1, Integer::sum);

				boolean showsNothing = false;

				// A diagnostic must never be able to fail the run it is describing.
				try {
					for (ParticleDiagnostics.Diagnostic diagnostic : ParticleDiagnostics.analyse(definition)) {
						findings.computeIfAbsent(
										diagnostic.severity() + " [" + diagnostic.code() + "] "
												+ diagnostic.message(),
										key -> new ArrayList<>())
								.add(file.getFileName().toString());

						showsNothing |= diagnostic.severity() == ParticleDiagnostics.Severity.ERROR;
					}
				} catch (Exception broken) {
					findings.computeIfAbsent("WARNING [diagnostic-failed] " + broken,
							key -> new ArrayList<>()).add(file.getFileName().toString());
				}

				if (showsNothing)
					invisible++;
			} catch (Exception rejected) {
				// Group by the message so one root cause does not print 60 times.
				String reason = rejected.getMessage() == null ? rejected.toString() : rejected.getMessage();

				rejections.computeIfAbsent(reason, key -> new ArrayList<>())
						.add(file.getFileName().toString());
			}
		}

		int rejectedCount = rejections.values().stream().mapToInt(List::size).sum();

		System.out.println("files       : " + files.size());
		System.out.println("load OK     : " + loaded);
		System.out.println("REJECTED    : " + rejectedCount);
		System.out.println("SHOW NOTHING: " + invisible + "  (load fine, but draw nothing)");
		System.out.println();

		if (!rejections.isEmpty()) {
			System.out.println("=== effects that will NOT play ===");

			rejections.forEach((reason, affected) -> {
				System.out.println();
				System.out.println("  " + affected.size() + " file(s): " + reason);

				affected.stream().limit(6).forEach(name -> System.out.println("      " + name));

				if (affected.size() > 6)
					System.out.println("      ... and " + (affected.size() - 6) + " more");
			});

			System.out.println();
		}

		if (!unsupported.isEmpty()) {
			System.out.println("=== components ignored (effect loads, behaviour is lost) ===");

			unsupported.entrySet().stream()
					.sorted((a, b) -> Integer.compare(b.getValue(), a.getValue()))
					.forEach(entry -> System.out.printf("  %4d x %s%n", entry.getValue(), entry.getKey()));

			System.out.println();
		}

		if (!findings.isEmpty()) {
			System.out.println("=== semantic findings (parse fine, may not look right) ===");

			findings.entrySet().stream()
					.sorted((a, b) -> Integer.compare(b.getValue().size(), a.getValue().size()))
					.forEach(entry -> {
						System.out.println();
						System.out.println("  " + entry.getValue().size() + " file(s): " + entry.getKey());

						entry.getValue().stream().limit(6)
								.forEach(name -> System.out.println("      " + name));

						if (entry.getValue().size() > 6)
							System.out.println("      ... and " + (entry.getValue().size() - 6) + " more");
					});

			System.out.println();
		}

		List<Map.Entry<String, List<String>>> duplicates = identifiers.entrySet().stream()
				.filter(entry -> entry.getValue().size() > 1)
				.sorted((a, b) -> Integer.compare(b.getValue().size(), a.getValue().size()))
				.toList();

		if (!duplicates.isEmpty()) {
			// Two effects with one identifier is legal in a pack but ambiguous on import: whichever
			// is imported second silently takes the name.
			System.out.println("=== duplicate identifiers ===");

			duplicates.forEach(entry ->
					System.out.println("  " + entry.getKey() + " -> " + String.join(", ", entry.getValue())));
		}
	}
}
