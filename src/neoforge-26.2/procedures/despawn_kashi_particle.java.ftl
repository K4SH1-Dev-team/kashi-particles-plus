<#--
	Ends every currently-running instance of a KASHI effect matching (effect, entity) - identical
	matching to stop_kashi_particle.java.ftl (see its own comment for the NO_ENTITY sentinel and
	why an event-chained child effect is never reachable this way), but a full instant cutoff:
	KashiParticleAPI.despawnKashiParticle also removes every particle already spawned, instead of
	letting them fade out the way Stop does. See despawnKashiParticle's own doc comment.

	entity comes pre-filled with entity_from_deps (see despawn_kashi_particle.json's toolbox_init),
	same as the Stop block - but can also be disconnected on purpose: "no entity" is a valid,
	common target (despawning a world/block spawn), not a missing value to guard against.
	input$entity!"null" is the same FreeMarker fallback stop_kashi_particle.java.ftl already uses.

	The effect id transform below MUST stay byte-for-byte identical to the same line in this
	generator's own entity_attach_kashi_particle.java.ftl/stop_kashi_particle.java.ftl (and the
	other 3 generators' copies of all three files) - see entity_attach_kashi_particle.java.ftl's
	own comment for why. A drift here does not fail the build; it just makes Despawn silently
	never match anything for this generator.
-->
if (world instanceof net.minecraft.world.level.Level _kashiLevel${cbi})
	net.kashi.particles.runtime.KashiParticleAPI.despawnKashiParticle(_kashiLevel${cbi},
		net.minecraft.resources.Identifier.fromNamespaceAndPath(
			net.kashi.particles.runtime.KashiParticlesRuntime.MODID,
			"${field$effect?replace("CUSTOM:", "")?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case}"),
		${input$entity!"null"});
