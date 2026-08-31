<#--
	Fires a KASHI effect at a world position, unaimed.

	The zero direction means world space: the effect keeps the orientation it was authored with in
	Snowstorm, with up still up. That is what AOE-style effects need - aiming them would tip the
	whole effect over.

	Fully-qualified names throughout, because a procedure's generated file has no imports of ours.

	The effect id reproduces MCreator's own registryName transform - see
	entity_spawn_kashi_particle_from_target.java.ftl for why this is neither generator.map() nor a
	plain lower-case, and where the regex below is verified against all 281 imported effects.
-->
if (world instanceof net.minecraft.world.level.Level _kashiLevel${cbi})
	net.kashi.particles.runtime.KashiParticleAPI.spawnKashiParticle(_kashiLevel${cbi},
		net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(
			net.kashi.particles.runtime.KashiParticlesRuntime.MODID,
			"${field$effect?replace("CUSTOM:", "")?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case}"),
		${input$x}, ${input$y}, ${input$z}, 0, 0, 0);
