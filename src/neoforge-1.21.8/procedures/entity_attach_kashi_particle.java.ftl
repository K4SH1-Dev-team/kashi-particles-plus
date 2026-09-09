<#--
	Fires a KASHI effect and keeps it following an entity every tick, anchored at a chosen point
	(root/body, head, eye) - an aura, fire on the feet, energy in a hand - instead of spawning once
	at a fixed position the way entity_spawn_kashi_particle_from_target.java.ftl does.

	The offset/aim/attach maths all live in KashiParticleAPI.attachToEntity rather than here, for
	the same reason spawnFromEntity's does: one readable Java method instead of branching
	freemarker, so the same rules apply wherever the API is called from. See that method's doc
	comment for what "attach" actually changes versus a one-shot spawn - most importantly, this is
	still bounded by the emitter's own fire-and-forget lifetime cap (at most 30 seconds of
	following for a looping effect), not a truly indefinite attachment.

	scale/duration are additive offsets on top of what the effect authored, both defaulting to 0 -
	see world_spawn_kashi_particle.java.ftl for what they do. The !0 default matters here beyond
	the toolbox default: a procedure element saved before this input existed has no value node for
	it at all in its stored Blockly XML, and without !0 that is a FreeMarker
	InvalidReferenceException on every regenerate - MCreator does not retroactively add missing
	inputs to an already-saved block, only a freshly dragged one gets the toolbox_init default.

	The effect id is field$effect (e.g. "CUSTOM:ThunderTrail") with the prefix stripped and put
	through the SAME transform MCreator's own registryName generation uses, reproduced here because
	nothing in the template API exposes it directly - see
	entity_spawn_kashi_particle_from_target.java.ftl for why (generator.map() and a plain
	?lower_case were both tried and both wrong).
-->
if (world instanceof net.minecraft.world.level.Level _kashiLevel${cbi})
	net.kashi.particles.runtime.KashiParticleAPI.attachToEntity(_kashiLevel${cbi},
		net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(
			net.kashi.particles.runtime.KashiParticlesRuntime.MODID,
			"${field$effect?replace("CUSTOM:", "")?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case}"),
		${input$entity}, ${input$right}, ${input$up}, ${input$forward}, "${field$aim}", "${field$attach}",
		(float) (${input$scale!0}), (float) (${input$duration!0}));
