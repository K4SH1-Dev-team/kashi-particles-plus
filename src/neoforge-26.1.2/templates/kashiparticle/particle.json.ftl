<#--
	Writes the imported Snowstorm .particle.json into the mod's resources, verbatim.

	The file is emitted exactly as the user imported it: the wizard already validated that it
	parses, and the runtime re-parses it at registration. Keeping it byte-for-byte means what
	plays in-game is the same effect the author exported from Snowstorm, with nothing rewritten
	in between.

	data.particleJson can still be null here: the wizard's "Import .particle.json..." step is the
	only thing that ever sets it, and nothing currently stops the element from being saved without
	ever clicking it (see the TODO in KashiParticleElementGUI - MCreator's validation API for
	blocking save isn't wired up yet). Interpolating null directly would throw a raw FreeMarker
	InvalidReferenceException and abort code generation for the whole mod over one empty element.
	Emitting a shape-less shell instead fails the exact same way a real broken import does: the
	runtime's own parser rejects it with a clear "no emitter_shape" message, the effect is skipped
	rather than crashing anything, and it shows up in KashiParticleRegistry.failures() same as any
	other bad effect - see KashiDebugCommand's "report" output.
-->
<#if data.particleJson??>
${data.particleJson}
<#else>
{"format_version": "1.10.0", "particle_effect": {
	"description": {"identifier": "kashi:missing_particle_json", "basic_render_parameters":
		{"material": "particles_alpha", "texture": "textures/particle/particle"}},
	"components": {}}}
</#if>
