<#--
	Fires a KASHI effect at a world position, aimed by an explicit direction vector.

	A zero direction (the default) means world space: the effect keeps the orientation it was
	authored with in Snowstorm, with up still up. That is what AOE-style effects need. A non-zero
	direction turns the whole effect to face that way - there is no entity here to read a look
	direction off, so unlike the entity-spawn block this takes the vector directly rather than an
	aim mode; see KashiParticleAPI.spawnKashiParticle for how it is consumed (same aimQuaternion
	machinery as the entity block's "aim").

	scale/duration are additive offsets on top of what the effect authored, both defaulting to 0
	(no change - Snowstorm stays the source of truth when nothing is filled in). duration is
	specifically active_time - how long the emitter keeps spawning new particles - not any single
	particle's own lifetime.

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
		${input$x}, ${input$y}, ${input$z}, ${input$dirx}, ${input$diry}, ${input$dirz},
		(float) (${input$scale}), (float) (${input$duration}));
