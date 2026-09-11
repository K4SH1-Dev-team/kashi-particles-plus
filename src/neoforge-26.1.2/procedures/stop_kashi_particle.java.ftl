<#--
	Ends every currently-running instance of a KASHI effect matching (effect, entity) - see
	KashiParticleAPI.stopKashiParticle's doc comment for exactly what "matching" means (the
	NO_ENTITY sentinel when entity is left unconnected, and why an event-chained child effect is
	never reachable this way).

	entity is deliberately left unconnected by default (see stop_kashi_particle.json's
	toolbox_init, which - unlike entity_attach_kashi_particle.json's - has no entry for it): "no
	entity" is itself a valid, common target (stopping a world/block spawn), not a missing value to
	guard against. The input$entity!"null" fallback below is the same FreeMarker mechanism
	entity_attach_kashi_particle.java.ftl already uses for scale/duration (there, for saved-block
	back-compat; here, because the socket starts empty on purpose) - it renders the literal Java
	null, which stopKashiParticle already treats as "no owning entity", the same way
	spawnFromEntity/attachToEntity already treat a null entity input.

	The effect id transform below MUST stay byte-for-byte identical to the same line in this
	generator's own entity_attach_kashi_particle.java.ftl (and the other 3 generators' copies of
	both files) - see that file's own comment for why (nothing in the template API exposes
	MCreator's registryName transform directly). A drift here does not fail the build; it just
	makes Stop silently never match anything for this generator.
-->
if (world instanceof net.minecraft.world.level.Level _kashiLevel${cbi})
	net.kashi.particles.runtime.KashiParticleAPI.stopKashiParticle(_kashiLevel${cbi},
		net.minecraft.resources.Identifier.fromNamespaceAndPath(
			net.kashi.particles.runtime.KashiParticlesRuntime.MODID,
			"${field$effect?replace("CUSTOM:", "")?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case}"),
		${input$entity!"null"});
