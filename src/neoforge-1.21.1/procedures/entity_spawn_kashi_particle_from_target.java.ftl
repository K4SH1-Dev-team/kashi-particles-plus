<#--
	Fires a KASHI effect from an entity, offset from its feet and turned by the chosen aim mode.

	The offset and the aim maths live in KashiParticleAPI rather than here, so the behaviour is one
	readable Java method instead of branching freemarker - and so the same rules apply wherever the
	API is called from.

	scale/duration are additive offsets on top of what the effect authored, both defaulting to 0 -
	see world_spawn_kashi_particle.java.ftl for what they do. The !0 default matters here beyond
	the toolbox default: a procedure element saved before this input existed has no value node for
	it at all in its stored Blockly XML, and without !0 that is a FreeMarker
	InvalidReferenceException on every regenerate - MCreator does not retroactively add missing
	inputs to an already-saved block, only a freshly dragged one gets the toolbox_init default.

	The effect id is field$effect (e.g. "CUSTOM:ThunderTrail") with the prefix stripped and put
	through the SAME transform MCreator's own registryName generation uses, reproduced here because
	nothing in the template API exposes it directly. Two things this is deliberately NOT, both
	tried and both wrong:

	  - generator.map() against this datalist: it only resolves CUSTOM: references for MCreator's
	    own built-in datalists (sounds, projectiles, ...). For one this plugin defines entirely
	    itself it has nothing to look up and hands back something close to the raw field - capitals
	    and all, an invalid ResourceLocation that crashes on first use, and once even the WRONG
	    element's name entirely.
	  - a plain ?lower_case: "ThunderTrail" becomes "thundertrail", but the element is actually
	    registered as "thunder_trail" - MCreator inserts an underscore at each camelCase boundary.
	    The two agree only for names with no internal case boundary ("Parry" -> "parry"), so this
	    silently broke every multi-word effect: no exception, the particle provider just returns
	    null for an id nothing was registered under.

	Confirmed by comparing this exact transform against the registered name of all 281 imported
	effects: 280 match; the one exception is a hand-made element from before this pack existed,
	which keeps the name MCreator assigned it through the wizard rather than recomputing one.
-->
if (world instanceof net.minecraft.world.level.Level _kashiLevel${cbi})
	net.kashi.particles.runtime.KashiParticleAPI.spawnFromEntity(_kashiLevel${cbi},
		net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(
			net.kashi.particles.runtime.KashiParticlesRuntime.MODID,
			"${field$effect?replace("CUSTOM:", "")?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case}"),
		${input$entity}, ${input$right}, ${input$up}, ${input$forward}, "${field$aim}",
		(float) (${input$scale!0}), (float) (${input$duration!0}));
