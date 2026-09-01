package net.kashi.particles.runtime;

import com.mojang.brigadier.arguments.StringArgumentType;
import com.mojang.brigadier.builder.LiteralArgumentBuilder;
import com.mojang.brigadier.builder.RequiredArgumentBuilder;

import net.neoforged.api.distmarker.Dist;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.client.event.RegisterClientCommandsEvent;

import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.commands.CommandSourceStack;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.phys.Vec3;

import java.util.stream.Collectors;

/**
 * A client-only debug command that fires an imported effect a few blocks in front of the player,
 * aimed along their look direction.
 *
 * <p>It exists to eyeball an effect without wiring a procedure, and it spawns through the very same
 * {@link KashiParticleAPI} the procedures use, so what it proves carries over. Running it with no
 * argument lists the effects this mod registered.
 *
 * <p>The command name folds in {@link KashiParticlesRuntime#MODID}, not just "kashiparticle": this
 * plugin can build more than one mod, and if two of them end up loaded in the same instance - two
 * separate mods a player installed together, both made with it - a bare "kashiparticle" literal
 * would collide. Brigadier command names are one global namespace with no built-in way to scope
 * them by mod the way block and item registries do (the "modid:path" convention is a
 * ResourceLocation thing, not something the command dispatcher understands), so MODID is folded
 * into the literal itself to guarantee two different mods never register the same command.
 *
 * <p>This is the NeoForge 1.21.8 variant of this file (see {@code runtime-1.21.8/} and
 * {@code tools/make-runtime-templates.ps1}) — identical to the 1.21.1 one except for the
 * {@code @EventBusSubscriber} annotation: see {@link KashiParticlesRuntime}'s 1.21.8 variant for
 * why {@code bus = EventBusSubscriber.Bus.GAME} is gone here too -
 * {@link RegisterClientCommandsEvent} does not implement {@code IModBusEvent}, so it was always
 * going to the NeoForge/game bus regardless, and still is now that the routing is implicit.
 */
@EventBusSubscriber(modid = KashiParticlesRuntime.MODID, value = Dist.CLIENT)
public final class KashiDebugCommand {

	/** e.g. "kashiparticle_mymod" for a mod whose id is "mymod". */
	private static final String COMMAND_NAME = "kashiparticle_" + KashiParticlesRuntime.MODID;

	private KashiDebugCommand() {
	}

	@SubscribeEvent
	static void onRegisterCommands(RegisterClientCommandsEvent event) {
		LiteralArgumentBuilder<CommandSourceStack> command =
				LiteralArgumentBuilder.<CommandSourceStack>literal(COMMAND_NAME)
						.executes(context -> {
							context.getSource().sendSuccess(() -> Component.literal(
									"KASHI effects: " + registeredNames()), false);

							// Effects that failed to load are skipped rather than crashing the
							// client, so this is the only place their absence is explained.
							KashiParticleRegistry.failures().forEach((id, reason) ->
									context.getSource().sendFailure(Component.literal(
											"FAILED to load '" + id.getPath() + "': " + reason)));

							return 1;
						});

		// /kashiparticle report - what every effect fired so far actually did. The point of a mass
		// test is finding the ones that show nothing, and they all look the same from the outside.
		command.then(LiteralArgumentBuilder.<CommandSourceStack>literal("report")
				.executes(context -> report(context.getSource(), false)));

		command.then(LiteralArgumentBuilder.<CommandSourceStack>literal("reportall")
				.executes(context -> report(context.getSource(), true)));

		command.then(LiteralArgumentBuilder.<CommandSourceStack>literal("reset")
				.executes(context -> {
					KashiDiagnostics.clear();
					context.getSource().sendSuccess(() -> Component.literal("KASHI counters cleared"), false);

					return 1;
				}));

		command.then(RequiredArgumentBuilder
				.<CommandSourceStack, String>argument("effect", StringArgumentType.word())
				.executes(context -> fire(context.getSource(),
						StringArgumentType.getString(context, "effect"))));

		event.getDispatcher().register(command);
	}

	/**
	 * Prints what each effect fired this session did, worst first.
	 *
	 * @param everything whether to include the effects that behaved; by default only the ones worth
	 *                   looking at are listed, because a sweep of 281 effects is unreadable otherwise
	 */
	private static int report(CommandSourceStack source, boolean everything) {
		if (KashiDiagnostics.records().isEmpty()) {
			source.sendSuccess(() -> Component.literal(
					"No KASHI effect has been fired yet - trigger some, then run this again."), false);

			return 0;
		}

		int wrong = 0;

		for (java.util.Map.Entry<String, KashiDiagnostics.Record> entry
				: new java.util.TreeMap<>(KashiDiagnostics.records()).entrySet()) {
			KashiDiagnostics.Record record = entry.getValue();

			if (record.looksWrong())
				wrong++;
			else if (!everything)
				continue;

			String line = entry.getKey() + ": " + record.verdict();

			if (record.looksWrong())
				source.sendFailure(Component.literal(line));
			else
				source.sendSuccess(() -> Component.literal(line), false);
		}

		int total = KashiDiagnostics.records().size();
		int broken = wrong;

		source.sendSuccess(() -> Component.literal(
				"KASHI: " + (total - broken) + " of " + total + " fired effects drew something."), false);

		return 1;
	}

	private static int fire(CommandSourceStack source, String effectName) {
		// Spawn directly on the client: this is a client command and particles live client-side,
		// so we use the ClientLevel rather than the source's ServerLevel.
		Minecraft mc = Minecraft.getInstance();
		LocalPlayer player = mc.player;

		if (player == null || mc.level == null)
			return 0;

		ResourceLocation id = ResourceLocation.fromNamespaceAndPath(
				KashiParticlesRuntime.MODID, effectName);

		if (!KashiParticleRegistry.contains(id)) {
			source.sendFailure(Component.literal(
					"No KASHI effect '" + effectName + "'. Available: " + registeredNames()));

			return 0;
		}

		// Aim along the FULL look direction, pitch included: a directional effect fired while
		// looking up should travel up. World-space (non-aimed) spawns pass a zero direction.
		Vec3 aim = player.getLookAngle();
		Vec3 origin = player.getEyePosition().add(aim.scale(3.0));

		// The player is named as the anchor so an effect declaring emitter_local_space behaves here
		// exactly as it will from a procedure; effects that do not declare it ignore this.
		KashiParticleAPI.spawnKashiParticle(mc.level, id,
				origin.x, origin.y, origin.z, aim.x, aim.y, aim.z, player.getId());

		source.sendSuccess(() -> Component.literal("Fired KASHI effect '" + effectName + "'"), false);

		return 1;
	}

	private static String registeredNames() {
		if (KashiParticleRegistry.ids().isEmpty())
			return "(none registered)";

		return KashiParticleRegistry.ids().stream()
				.map(ResourceLocation::getPath)
				.sorted()
				.collect(Collectors.joining(", "));
	}
}
