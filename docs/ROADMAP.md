# Roadmap

## Onde estamos

**v4.0.0** publicado ([Releases](https://github.com/K4SH1-Dev-team/kashi-particles-plus/releases))
— paridade completa com o Snowstorm 3.2.2 para o formato `.particle.json`, endurecido para uso em
produção em workspaces diferentes da de desenvolvimento, escala/duração aditivos e broadcast
confiável em multiplayer (v2.0.0), suporte ao gerador NeoForge 1.21.8 lado a lado com o 1.21.1
(v2.5.0), duas correções de estabilização descobertas em build real no MCreator (v2.5.1), porte
completo para o MCreator 2026.2 com suporte a **dois novos geradores** (NeoForge 26.1.2 e 26.2)
lado a lado com o 1.21.1/1.21.8 (v3.0.0), e três blocos novos — **Attach K4SH1 Particle to
Entity**, **Stop K4SH1 Particle** e **Despawn K4SH1 Particle** — fechando a lista de ideias
original do usuário (v4.0.0). Ver histórico completo abaixo.

## Próximas fases

### Fase 3 — Melhorias e correções (concluída)
4 melhorias no wizard e nos procedures: bloqueio de salvar um elemento sem `.particle.json`
importado; mensagem correta no seletor de efeito (`dialog.selector.kashiparticle.message`); spawn
a partir de entidade ancorado nos pés em vez dos olhos; direção opcional adicionada aos blocos de
spawn no mundo e a partir de bloco (antes só o bloco de entidade tinha aim). Também nesta janela:
correção da caixa de frustum culling (diagonal em vez de `max`), correção do sinal de roll em
`lookat_direction`/`direction_x/y/z`, rotação de `linear_acceleration` pela mira, eliminação de
alocação por frame no render, e um reforço visual completo do wizard de importação (resumo mais
rico, diagnósticos fixos na tela, arrastar-e-soltar).

### V2 — escala/duração aditivos e correção do broadcast (concluída)
A partir de uma lista de ideias do usuário (`Spawn`/`Play`/`Stop`/`Attach`/`Set Variable`
organizados em torno de um conceito de "Particle Instance"), o que foi validado e implementado:

- **Escala e duração aditivas** nos 3 blocos de spawn (`scale`, `duration`, ambos default `0` = sem
  mudança, Snowstorm continua a fonte da verdade). `duration` afeta só o `active_time` do emissor
  (quanto tempo ele continua nascendo partículas novas), não o `max_lifetime` de cada partícula.
- **Correção do envio de partícula**: o broadcast do servidor para múltiplos clientes usava
  `level.addParticle`, que tem corpo vazio em `ServerLevel` — um no-op mascarado por singleplayer
  (nunca testado em multiplayer real nesta sessão). Trocado por `ServerLevel.sendParticles(...,
  longDistance = true, ...)`, que também amplia o raio de transmissão de 32 para 512 blocos.

Descartado ou adiado desta lista, com o motivo:

- **Direção/aim configurável no spawn** — descartado pelo usuário, sem necessidade identificada.
- **Distância máxima configurável** — descartada: o pedido real era garantia de visibilidade a
  longa distância, resolvido pela correção do broadcast acima; nenhum teto novo era necessário.
- **Set K4SH1 Particle Variable** — descartado pelo usuário ("não estou achando muito útil").
- **Stop K4SH1 Particle** e **Attach K4SH1 Particle to entity** — ambos implementados, ver
  "V4.0.0" abaixo.

### V2.5 — Porte para NeoForge 1.21.8 (concluída)
O MCreator 2026.1.x já oferece o gerador NeoForge 1.21.8 além do 1.21.1; o plugin agora suporta os
dois lado a lado (nenhum foi substituído). Investigação feita contra a API real dos dois geradores
(`javap`/leitura de fonte a partir dos jars "merged" reais de cada workspace de teste, não
suposição): a esmagadora maioria do `runtime/` (11 de 13 arquivos) é idêntica entre as duas
versões — só 5 arquivos genuinamente divergem, isolados numa pasta de overlay
(`runtime-1.21.8/`) em vez de duplicar a árvore inteira:

- `KashiParticleAPI.java` — `ServerLevel.sendParticles` ganhou um parâmetro booleano a mais
  (`alwaysShow`) no 1.21.8; o antigo `longDistance` virou `overrideLimiter`, mesmo papel.
- `KashiRenderType.java` — `ParticleRenderType` é uma interface no 1.21.1 e virou um `record` no
  1.21.8 (não dá mais pra implementar); o sistema de blend do Minecraft passou de imperativo
  (`RenderSystem`/`GlStateManager`) para declarativo (`RenderPipeline`/`BlendFunction`). Reescrito
  seguindo o mesmo padrão que o próprio vanilla usa pros particles dele.
- `KashiParticlesRuntime.java`, `KashiParticleClient.java`, `KashiDebugCommand.java` — o atributo
  `bus` de `@EventBusSubscriber` foi removido no 1.21.8; o bus correto agora é inferido
  automaticamente por tipo de evento (`IModBusEvent` → mod bus, senão → game bus), então essas 3
  classes só deixam de declarar `bus` explicitamente — o roteamento continua o mesmo.

Ver [ARCHITECTURE.md](ARCHITECTURE.md) — "Two generators, one shared runtime" para o mecanismo de
overlay, e [DEVELOPMENT.md](DEVELOPMENT.md) para as duas workspaces de teste
(`kashi_particle_test` / `teste_vinte_oito`).

#### v2.5.1 — dois bugs reais pegos só no build MCreator/Gradle (concluída)

`check-mod-compile.ps1` (javac puro) não pegou nenhum dos dois — só um build de verdade dentro do
MCreator revelou:

- **`InvalidReferenceException: input$scale evaluated to null or missing`** em 289 elementos: o
  MCreator não adiciona retroativamente um input novo (`scale`/`duration`/`dirx`/`diry`/`dirz`) ao
  XML Blockly de um elemento salvo antes desses inputs existirem. Corrigido com o operador de
  valor-padrão do FreeMarker (`${input$scale!0}`) nos 3 templates de procedure, nos dois
  geradores — `0` já significava "sem mudança", então não muda comportamento nenhum para quem já
  tinha o valor salvo.
- **Colisão de import**: o formatter de código do próprio MCreator injetou
  `import net.minecraft.client.sounds.Weighted;` dentro do `KashiParticleDefinition.java`
  templatizado, colidindo com o nosso próprio `record Weighted` aninhado — só no gerador 1.21.8.
  Corrigido renomeando o tipo para `WeightedOption`. Ver [CLAUDE.md](CLAUDE.md) — "The traps most
  worth not re-discovering" para os detalhes e por que isso é invisível ao `check-mod-compile.ps1`.

Testado manualmente pelo usuário nas duas workspaces após a correção: build OK, os 4 modos de
blend visualmente corretos, broadcast a longa distância confirmado.

### Fase 4 / V3.0.0 — Porte para MCreator 2026.2 (concluída)
Maior que a V2.5: aqui mudam duas coisas ao mesmo tempo — o aplicativo MCreator em si (2026.1 →
2026.2, com sua própria API de plugin) e a API Minecraft/NeoForge por trás de dois geradores novos
(`neoforge-26.1.2` e `neoforge-26.2`; o `1.21.8` já foi feito na V2.5 acima). Matriz final: MCreator
2026.1 → `1.21.1`/`1.21.8`; MCreator 2026.2 → `1.21.1`/`26.1.2`/`26.2`.

**Etapa A concluída** (não dependia de novas workspaces):

- `src/plugin.json` ganhou `2026002` em `supportedversions` — sem isso o MCreator 2026.2
  provavelmente nem ofereceria o plugin (confirmado comparando com o `plugin.json` do próprio
  gerador `generator-26.2.x`).
- `src-java/` + `core/` compilam sem nenhuma mudança contra a API de plugin (`net.mcreator.*`) do
  MCreator 2026.2 — confirmado compilando de verdade contra o `mcreator.exe` extraído dessa
  instalação, não suposto.
- Pipeline inteira (`build-plugin.ps1`, `check-mod-compile.ps1`, `run-core-tests.ps1`) generalizada
  pra uma tabela de instalações — os dois MCreators isolados (`local/mcreator` = 2026.1/JDK 21,
  `local/02 - MCreator20262` = 2026.2/JDK 25) não são intercambiáveis, os dois geradores novos
  exigem Java 25 de verdade (`build.gradle` de cada um, não preferência do MCreator).
- Workspace `true_particle_test` (MCreator 2026.2, gerador `neoforge-1.21.1`) sincronizada e
  type-checada contra o merged jar real — OK, mesmo build NeoForge (`21.1.190`) que sob o MCreator
  2026.1. Achado à parte: sob o app 2026.2 o mesmo gerador `1.21.1` já mostra
  `@EventBusSubscriber(bus = ...)` como `[removal]`-deprecated (ainda compila) — sinal de que essa
  mesma correção que o `1.21.8` já recebeu pode um dia ser necessária ali também. Ver
  [CLAUDE.md](CLAUDE.md).
- `generator-addon-26.1x` identificado e descartado do escopo — é um gerador **Bedrock Edition**
  (behavior/resource pack), não Java/NeoForge.

**Etapa B concluída** — usuário criou as duas workspaces novas (`seis_um` = `neoforge-26.1.2`,
`seis_dois` = `neoforge-26.2`) e buildou cada uma no MCreator; a partir dos merged jars reais
(`javap`/leitura de fonte, nunca suposição), a API confirmada divergir de verdade foi bem maior que
o salto do 1.21.8 — quase todo `runtime/` precisou de overlay, não só 2-3 arquivos:

- `ResourceLocation` renomeada pra `Identifier` (mesma API, só o nome) — afeta quase todo arquivo
  que toca um id de efeito ou textura.
- `@EventBusSubscriber(bus = ...)` removido (igual ao 1.21.8), `Level.random` virou `protected`
  (`getRandom()`), `Camera.getPosition()` virou `Camera.position()`.
- **O pipeline de render de partículas foi reconstruído** em torno de "extrai os dados do frame,
  desenha depois" em vez de "cada partícula desenha a si mesma num `VertexConsumer`" —
  `Particle.render(...)` não existe mais. `KashiParticle` ganhou dois arquivos sem equivalente no
  1.21.x, `KashiParticleGroup.java` e `KashiParticleRenderState.java`, registrados uma vez (não por
  efeito) via `RegisterParticleGroupsEvent` da NeoForge — reimplementando o próprio padrão de
  batching por (textura, blend) que o vanilla usa (`SingleQuadParticle`/`QuadParticleRenderState`),
  mas com largura/altura independentes (o vanilla só guarda um `scale` único por partícula — um
  KASHI particle tem `size.x`/`size.y` autorados separadamente).
- **`26.1.2` e `26.2` nem concordam entre si** nessa mesma API — confirmado comparando os dois jars
  reais, não suposto de um pro outro — por isso viraram dois overlays separados
  (`runtime-26.1.2/`, `runtime-26.2/`) em vez de compartilhado. `26.1.2` exige implementar
  `SubmitNodeCollector.ParticleGroupRenderer` (monta os buffers de GPU na mão); `26.2` simplificou
  pra um `buildLayer(Layer, VertexConsumer)` direto, mas exige que a classe seja literalmente uma
  subclasse de `QuadParticleRenderState` (o método que a recebe é tipado pra classe concreta, não
  uma interface).
- `Particle.getRenderBoundingBox` (a caixa de frustum culling customizada) também sumiu — culling
  agora é decisão de cada `ParticleGroup`. `KashiParticleGroup` usa `Frustum.isVisible(AABB)` contra
  uma caixa que `KashiParticle` ainda calcula do jeito antigo, pra não reintroduzir silenciosamente
  o bug de culling que aquele método existia pra corrigir.
- `neoforge-26.1.2`/`neoforge-26.2` não escrevem `clientLegacyClasspath.txt` — `check-mod-compile.ps1`
  resolve o classpath rodando o Gradle uma vez (`tools/kashi-print-classpath.init.gradle`), com
  cache em disco depois disso.

Resultado: as cinco workspaces (`kashi_particle_test`, `teste_vinte_oito`, `true_particle_test`,
`seis_um`, `seis_dois`) compilam limpo via `check-mod-compile.ps1`, e `run-core-tests.ps1` passa
sob os dois JDKs.

#### Quatro bugs reais pegos só em teste real (build Gradle + jogo, não `check-mod-compile.ps1`)

Mesmo padrão da v2.5.1 acima — `check-mod-compile.ps1` não pegou nenhum dos quatro:

- **`ResourceLocation` nos procedures de `26.1.2`/`26.2`**: os 3 templates de procedure desses dois
  geradores foram copiados byte-a-byte do `1.21.1` na suposição de que "procedure nunca toca API
  divergente" — falsa aqui, já que fully-qualificam `ResourceLocation.fromNamespaceAndPath(...)`, e
  `check-mod-compile.ps1` nunca vê `src/<generator>/procedures/*.java.ftl`. Só um build Gradle real
  revelou. Corrigido trocando pra `Identifier` nos 6 arquivos.
- **`KashiParticleEffects.java.ftl` faltando em `26.1.2`/`26.2`**: o registro global de efeitos nunca
  foi copiado pra esses dois geradores quando foram criados. MCreator não falha o build quando um
  `global_templates` referencia um `.ftl` inexistente — só ignora silenciosamente. Nenhum efeito
  disparava, sem erro nenhum; só um teste em jogo (`/kashiparticle_<mod> report`) revelou. Ver
  [CLAUDE.md](CLAUDE.md).
- **Crash de textura durante o render pass** (`IllegalStateException: Close the existing render
  pass...`): o novo modelo de comando da GPU em 26.1.2/26.2 não permite carregar uma textura
  enquanto um render pass está aberto — e a primeira textura de um efeito KASHI só era carregada
  dentro do `render()`/`buildLayer()`, já dentro do pass. Corrigido pré-carregando a textura em
  `KashiRenderType.of()`, que roda na fase de "extract" (antes de qualquer pass abrir).
- **Blend `ADD` renderizando como um blob sem forma, só em `26.2`**: `Parry`, `Parry2`,
  `InsectZigzagParry` e `InsectZigzagParry2` (todos `material: particles_add`) ficavam um blob
  saturado sem forma reconhecível no `26.2`; `Stun`/`Nichirin` (blend alpha/cutout) sempre
  renderizaram certo. Geometria e ciclo de vida do `Storage` confirmados corretos via log real de
  jogo antes de achar a causa: `DepthStencilState.DEFAULT` mudou de `(LESS_THAN_OR_EQUAL, true)` no
  `26.1.2` pra `(GREATER_THAN_OR_EQUAL, true)` no `26.2` (depth invertido/reversed-Z) —
  `ADDITIVE_PIPELINE` sobrescreve esse compare op na mão (pra desligar `writeDepth`) e foi copiado
  do `26.1.2` com o operador antigo, o único errado pra convenção do `26.2`. Sem oclusão de
  profundidade correta, cada quad aditivo ficava se somando por cima do outro sem limite. Corrigido
  trocando pra `GREATER_THAN_OR_EQUAL` só no arquivo do `26.2`. Ver [CLAUDE.md](CLAUDE.md).

Testado pelo usuário nas 5 workspaces com build Gradle real: `kashi_particle_test`, `teste_vinte_oito`
e `true_particle_test` (1.21.1/1.21.8, já validados na v2.5/v2.5.1) e `seis_um`/`seis_dois`
(26.1.2/26.2, novos) — os 4 modos de blend (ADD/ALPHA/CUTOUT — não existe exemplo OPAQUE no pack
de prova) corretos nas 5.

### V4.0.0 — Attach, Stop e Despawn K4SH1 Particle (concluída)

As duas últimas ideias validadas da lista original (`Spawn`/`Play`/`Stop`/`Attach`/`Set Variable`)
— nesta versão o escopo acabou se dividindo em três blocos novos: Attach, Stop e Despawn.

#### Attach K4SH1 Particle to Entity

Prende um efeito a uma entidade em vez de a uma posição fixa, pra ele acompanhá-la (aura, fogo nos
pés, energia na mão). Escopo acordado desde o início: só vanilla, sem GeckoLib — Player e bipeds
vanilla (zumbi, esqueleto) + o modelo biped padrão do MCreator.

**Etapa A (root/body, head, eye)** — esforço baixo, reaproveitando a máquina de
`emitter_local_space` já existente, só ancorando num offset da entidade em vez de world-space. Um
único método compartilhado (`KashiParticleAPI.resolveAttachPoint`) resolve a posição dos 3 pontos,
chamado tanto no spawn inicial (que pode rodar no servidor) quanto no rastreio por tick
(client-only) — os dois nunca discordam sobre onde um ponto está. Rotação (yaw+pitch, "full look")
vive só no cliente, num método separado (`KashiEmitterParticle.followFrame`), reaproveitado depois
pela Etapa B.

Testado pelo usuário: a rotação de Head/Eye/Body pareceu não se mover a princípio ("não moveu") —
na investigação, a matemática de rotação (yaw+pitch, `aimQuaternion`) já estava correta desde o
início; era um artefato de visibilidade (o offset testado era pequeno demais pra notar a mudança
de ângulo a olho). Confirmado com um offset maior: "Sim, moveu". Nenhum bug de fato, só limpeza do
logging de diagnóstico temporário usado pra investigar (nunca chegou a ser commitado).

**Etapa B (braço/mão, perna/pé)** — esforço moderado, usando `entity.getAttackAnim`/
`entity.walkAnimation` (API pública e estável do próprio Minecraft, confirmada rodar igual em
servidor e cliente via decompilação real dos dois extremos de gerador — sem risco de "salto" no
primeiro frame). Requisito adicional do usuário durante o design: o efeito deve **rotacionar**
junto com o membro, não só mudar de posição — um soco deve inclinar um efeito na mão, uma passada
deve balançar um efeito no pé. Implementado como uma função de ângulo extra
(`resolveLimbSwingRadians`) que inclina o mesmo frame de rotação da Etapa A.

Bug real encontrado em teste: a mão renderizava presa na altura do ombro (`SHOULDER_HEIGHT`)
constante, independente da animação — inclusive parada, sem socar. Corrigido fazendo a altura
variar com `attack()` do mesmo jeito que o avanço (`forward`) já variava: pendura abaixo do ombro
em repouso (nova constante `ARM_DROP`), sobe até a altura do ombro num soco totalmente estendido.

#### Stop / Despawn K4SH1 Particle

A ideia original ("Stop") assumia precisar de um sistema de ID de instância e um pacote de rede
próprio — nenhum dos dois existia no plugin até aqui (todo spawn até então pegava carona no pacote
nativo de partícula do Minecraft). Decisão de design, confirmada com o usuário via duas perguntas
diretas: alvo por **entidade + efeito** (não um ID de instância novo — mais simples, evita reabrir
o território de "Set K4SH1 Particle Variable", já rejeitado antes), reaproveitando o mesmo
sentinela `NO_ENTITY` que `KashiParticleOptions` já carrega em todo spawn.

Implementado: um pacote S2C novo (`KashiStopParticlesPayload`), um registro client-only de
instâncias vivas (`KashiActiveParticles`, chaveado por efeito+entidade), e um novo método em
`KashiEmitterParticle` pra encerrar externamente. Só o emissor direto de um Spawn/Attach se
registra — um efeito disparado como evento encadeado de outro efeito nunca teve um id próprio pra
registrar, e nunca foi selecionável via bloco de qualquer forma.

Três bugs reais encontrados só em teste de verdade (nenhum pego por inspeção estática nem pelos
scripts de build):

- **No-op quando a procedure roda no lado cliente**: `stopKashiParticle` só tinha o ramo servidor
  (mandar o pacote) — ao contrário de `spawnKashiParticle`, que já tem um `else` pro caso
  client-side. Se a procedure que chama Stop roda no cliente (alguns tipos de gatilho do MCreator
  rodam), a chamada não fazia nada, silenciosamente. Corrigido espelhando o mesmo split
  client/servidor que o spawn já tinha.
- **Stop sozinho não bastava pro que o usuário queria**: Stop só encerra o emissor (para de nascer
  partícula nova) — o que já existia (partículas visíveis já lançadas têm vida própria e continuam
  na tela até acabar sozinhas, igual a uma expiração natural). Pra um efeito curto ou denso isso
  parece "não fez nada". Em vez de mudar a semântica do Stop (correta nos próprios termos), virou
  um segundo bloco: **Despawn K4SH1 Particle** — mesmo alvo, corte total e instantâneo, removendo
  também toda partícula já nascida.
- **Despawn não achava nada pra matar quando o emissor já tinha acabado sozinho**: o `active_time`
  do emissor termina bem antes das partículas que ele já lançou acabarem de sumir (`max_lifetime`
  próprio, geralmente mais longo) — e o emissor se desregistrava do rastreamento assim que
  terminava, então um Despawn chegando nessa janela não achava mais nada, mesmo com partículas
  visíveis na tela. Corrigido adiando o desregistro: o emissor só sai do registro quando ele mesmo
  já acabou **e** não sobra mais nenhuma partícula filha viva — o que vier por último.

Ajuste de UX pós-teste: os dois blocos vêm com a entrada `entity` já preenchida com
`entity_from_deps` por padrão (igual a Attach e Spawn from entity), já que o uso pretendido é
sempre mirar uma entidade específica — spawn de mundo/bloco (sem dono) fica fora do escopo de
Stop/Despawn por enquanto.

Todos os achados desta seção só apareceram em teste real dentro do jogo, com logging de
diagnóstico temporário adicionado e removido a cada rodada — nenhum foi visível por inspeção
estática nem pego pelos scripts de build (`check-mod-compile.ps1` nunca roda o FreeMarker de
verdade contra um bloco real de uma workspace).

#### Uma pegadinha de merge, duas vezes

Nas duas vezes em que uma PR desta versão foi mesclada (Etapa B do Attach, e depois Stop/Despawn),
o merge capturou a branch num ponto anterior a um commit de correção que ainda estava sendo
empurrado — o `main` ficou sem a correção mais recente até uma segunda PR trazer só os commits que
faltavam. Vale sempre conferir o `headRefOid` de um PR mesclado contra o HEAD real da branch antes
de dar uma feature por encerrada.

### V4.0.1 — Attach respeita o aim (concluída)

Versão de correção sobre a 4.0.0, achada ao montar um efeito de "energia na mão" (o charge de um
Kamehameha) num mod de verdade, não por inspeção estática. O `plugin.json` tinha ficado em `3.0.0`
na 4.0.0 (o commit de bump não foi feito); esta versão também corrige isso.

#### O `aim` do Attach só valia no instante do spawn

O dropdown `aim` decidia como o efeito era virado quando nascia; depois disso o emissor seguia
sempre o olhar completo (yaw e pitch) e girava o offset em torno dos **pés** (`followFrame()` em
`KashiEmitterParticle`), qualquer que fosse o modo escolhido. Um offset `up` num anchor root
(energia na altura do quadril, uma aura no peito) balançava em arco toda vez que a entidade olhava
pra cima ou pra baixo, mesmo com "turns with entity, stays level" selecionado.

Agora o modo viaja com o spawn (`aimMode` em `KashiParticleOptions.Extras`, opcional no codec,
padrão `FULL`) e escolhe o referencial que o emissor segue: `FULL` segue yaw e pitch (como antes),
`HORIZONTAL` só o yaw, `NONE` mantém os eixos do mundo e só acompanha a posição. `FULL` é o padrão,
então não muda nada pra quem já o usava; quem tinha `HORIZONTAL` ou `NONE` num Attach passa a ver o
efeito parar de inclinar com o pitch, que é o que o dropdown já descrevia. Aplicado nas 4 variantes
de runtime (PR #33).

#### Duas pegadinhas achadas no caminho

- **`emitter_local_space.velocity: true` faz as partículas herdarem o movimento da entidade**
  (`inheritedVelocity()` = `getDeltaMovement() × 20`). Em pé no chão o jogador tem velocidade
  vertical de ≈ −0,078/tick (a gravidade empurrando contra o piso), ≈ −1,57 blocos/s: um efeito
  anexado afunda no chão, enquanto voando a velocidade é 0 e ele fica parado — o sintoma "funciona no
  ar, afunda no chão". Pra efeitos presos a uma entidade o mais seguro é `velocity: false` no JSON
  (a posição já é seguida pelo emissor). Sem mudança de código: a herança é intencional (ver o
  comentário em `followAnchor()`), só ficou registrada aqui.
- **`check-mod-compile.ps1` não funcionava fora da máquina que construiu as workspaces**: os
  arquivos de classpath em cache guardam caminhos absolutos do cache do Gradle de quem construiu, e
  em outro perfil de usuário todo jar "não existia" — centenas de erros `package ... does not exist`
  e nenhum erro real visível (o `javac` nem checa tipos quando um import não resolve). Foi assim
  que um construtor esquecido no primeiro patch do Attach só apareceu no Build real do MCreator.
  Agora o script mapeia cada entrada pro cache local, nunca troca o jar do NeoForge (pula o
  workspace com o motivo) e termina listando o que foi checado e o que foi pulado (PR #34).

Testado: Build e jogo num mod real (workspace do Animeverse, NeoForge 26.2). Compilação via
`check-mod-compile.ps1`: 1.21.1 (MCreator 2026.1 e 2026.2), 1.21.8 e 26.2; o 26.1.2 não foi
compilado (o NeoForge 26.1.2.95 não está no cache da máquina de teste), mas as linhas alteradas em
`runtime-26.1.2` são idênticas às de `runtime-26.2`. Testes do core: 103 checagens sob JDK 21 e 25.

---

## Histórico: o plano de paridade Snowstorm

O que segue é o plano original que levou o plugin de um importador parcial a paridade completa
com o Snowstorm, usando os 279 arquivos de um resource pack Bedrock real (mantido fora do
repositório — ver `docs/DEVELOPMENT.md`) como banco de provas. Preservado como registro de por que
cada peça existe; todas as fases abaixo estão concluídas.

**Objetivo original:** o plugin aceita **tudo** que o Snowstorm 3.2.2 exporta e reproduz
**idêntico**.

### Onde o plano começou (17 de 20 componentes usados no pack já implementados)

| Componente | Arquivos |
|---|---|
| `particle_lifetime_expression` | 279 |
| `particle_appearance_billboard` (10 facings, flipbook) | 279 |
| `particle_initial_speed` | 277 |
| `particle_motion_dynamic` | 266 |
| `emitter_lifetime_once` | 257 |
| `particle_appearance_tinting` (gradiente + expressão) | 252 |
| `emitter_rate_instant` | 216 |
| `particle_initial_spin` | 196 |
| `emitter_shape_point` | 143 |
| `emitter_shape_disc` | 87 |
| `emitter_rate_steady` | 63 |
| `emitter_shape_sphere` | 48 |
| `emitter_lifetime_expression` | 11 |
| `emitter_lifetime_looping` | 9 |
| `particle_appearance_lighting` | 8 |
| `particle_motion_parametric` | 1 |
| `emitter_shape_box` | 1 |

### As lacunas que motivaram as fases

| Lacuna | Arquivos | Sintoma no jogo |
|---|---|---|
| **`curves`** (aba Variables & Curves) | **84** | `v.size` lê **0** → partícula de tamanho zero, **invisível** |
| **`emitter_local_space`** | **114** | não herda posição/rotação/velocidade do emissor |
| **`events` + `emitter_lifetime_events`** | 28 (324 nós) | efeitos encadeados nunca disparam |
| **`particle_motion_collision`** | 7 | atravessa blocos |
| `particle_kill_plane` | 0 no pack | — (paridade Snowstorm) |
| `expire_if_in_blocks` / `_not_in_blocks` | 0 no pack | — (paridade Snowstorm) |
| `emitter_shape_custom` / `entity_aabb` | 0 no pack | — (paridade Snowstorm) |

A lacuna de curvas era a mais grave: 42 arquivos escreviam `variable.size` numa curva e 40 liam
`v.size` no campo Size — sem curvas, isso valia 0, e a partícula desaparecia sem explicação.

### As 7 fases (todas concluídas)

1. **Curvas** *(84 arquivos)* — `particle_effect.curves` com os 4 tipos do Bedrock (`linear`,
   `catmull_rom`, `bezier`, `bezier_chain`), reavaliadas por tick no escopo certo
   (emissor vs partícula). Implementado em `core/.../CurveSampler.java`.
2. **`emitter_local_space`** *(114 arquivos)* — `position`/`rotation`/`velocity`: partículas
   passam a acompanhar a entidade que disparou o efeito. É o que liga o campo **Aim** das
   procedures ao interior do efeito.
3. **Eventos** *(28 arquivos, 324 nós)* — mapa `events` + gatilhos `emitter_lifetime_events`/
   `particle_lifetime_events`, nós `particle_effect`, `sound_effect`, `expression`, `log`,
   `randomize`, `sequence`. Implementado em `runtime/.../KashiEventRunner.java`. Um efeito que
   dispara outro exige que o outro também esteja importado — o wizard avisa disso.
4. **Colisão e expiração** — `particle_motion_collision` (7 arquivos), `kill_plane`,
   `expire_if_in_blocks`/`expire_if_not_in_blocks`.
5. **Restos de paridade** — `emitter_shape_custom`, `emitter_shape_entity_aabb`, e
   `particles_alpha` corrigido para alpha *test* (recorte) em vez de blend.
6. **Robustez** — cinco correções: `facing()` desconhecido degradava para exceção (rejeitando o
   arquivo inteiro) em vez de cair em `rotate_xyz` com aviso; `initialSpeed` escalar sendo lido
   como velocidade por eixo em vez de escalar-na-direção; `MolangCompiler` com array de slots
   curto quando algo compilava depois do primeiro contexto; `blendOf()` decidindo por substring
   do nome do material (um material customizado caía em alpha por sorte); identificadores
   duplicados no pack.
7. **Diagnóstico semântico** — `ParticleDiagnostics` (usado pelo validador em lote e pelo wizard):
   tamanho ou alpha zero em toda a vida, `max_frame` além do que a folha comporta, variável lida
   sem nunca ser definida, identificador duplicado.

### Situação ao fechar a paridade (22/07/2026)

Todas as fases concluídas. Dos 279 arquivos do pack de prova: 279 carregam, 0 rejeitados, nenhum
componente declarado por eles é ignorado. O que sobrou depois disso era autoria do pack, não bug
do plugin: 23 arquivos com `max_frame` além da folha, 1 com uma expressão MoLang inválida
(`math.round` com 2 argumentos numa função de 1), 1 lendo uma variável nunca definida.

### V1.0.0 — de "funciona nesta workspace" a produção portável (agosto/2026)

Depois da paridade, um teste em massa (todos os efeitos de um pack disparados juntos) revelou dois
problemas de *teste*, não de motor: alguns efeitos tinham offset de emissor muito acima do
jogador (conteúdo autoral, não bug), e efeitos curtos/rápidos perdiam o frame sob o lag severo de
disparar dezenas de efeitos pesados no mesmo tick (comportamento inerente do desacoplamento
tick/frame do Minecraft sob carga, não específico deste plugin). A decisão foi parar de perseguir
esses casos e, em vez disso, endurecer o plugin para produção:

- `KashiParticleType.overrideLimiter = true` — sem isso, efeitos disparados a mais de ~15-30
  blocos do jogador nunca criavam o emissor (achado via decompilação de
  `LevelRenderer.addParticle`).
- `tools/optimize-textures.py` — recompressão PNG sem perdas (re-deflate + paleta indexada,
  verificado byte-a-byte/pixel-a-pixel antes de aceitar).
- `ParticleDiagnostics.volumeFindings` — aviso no wizard quando um efeito importado estimaria
  mais de 2000 partículas.
- Tooltips dos blocos de procedure com aviso operacional sobre disparar muitos efeitos pesados no
  mesmo tick.
- `KashiDebugCommand` — nome do comando passou a incorporar o `MODID` (`/kashiparticle_<modid>`),
  evitando colisão se dois mods construídos com este plugin coexistirem num modpack.
- `particle.json.ftl` — passou a degradar graciosamente (em vez de travar a geração do mod
  inteiro) quando um elemento é salvo sem nunca importar um `.particle.json`.
- Testado do zero numa segunda workspace MCreator (modid diferente) para confirmar portabilidade
  de verdade, não só validação estática.
