<#--
	Fires a KASHI effect from the centre of a block, aimed by an explicit direction vector.

	The +0.5 on each axis moves the origin from the block's corner to its middle, which is where an
	effect visually belongs. Like the world spawn, a zero direction (the default) means world
	space, up stays up, so AOE effects sit flat on the block instead of leaning; a non-zero
	direction turns the whole effect to face that way - see world_spawn_kashi_particle.java.ftl.

	scale/duration are additive offsets on top of what the effect authored, both defaulting to 0 -
	see world_spawn_kashi_particle.java.ftl for what they do.

	dirx/diry/dirz and scale/duration all read with a !0 default, not just ${...}: a procedure
	element saved before one of these inputs existed has no value node for it at all in its stored
	Blockly XML, and without the default that is a FreeMarker InvalidReferenceException on every
	regenerate - MCreator does not retroactively add missing inputs to an already-saved block, only
	a freshly dragged one gets the toolbox_init default.

	The effect id reproduces MCreator's own registryName transform - see
	entity_spawn_kashi_particle_from_target.java.ftl for why this is neither generator.map() nor a
	plain lower-case, and where the regex below is verified against all 281 imported effects.
-->
if (world instanceof net.minecraft.world.level.Level _kashiLevel${cbi})
	net.kashi.particles.runtime.KashiParticleAPI.spawnKashiParticle(_kashiLevel${cbi},
		net.minecraft.resources.Identifier.fromNamespaceAndPath(
			net.kashi.particles.runtime.KashiParticlesRuntime.MODID,
			"${field$effect?replace("CUSTOM:", "")?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case}"),
		${input$x} + 0.5, ${input$y} + 0.5, ${input$z} + 0.5, ${input$dirx!0}, ${input$diry!0}, ${input$dirz!0},
		(float) (${input$scale!0}), (float) (${input$duration!0}));
