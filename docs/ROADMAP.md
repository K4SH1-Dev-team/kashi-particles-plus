# Roadmap

## Onde estamos

**v1.0.0** — paridade completa com o Snowstorm 3.2.2 para o formato `.particle.json`, endurecido
para uso em produção em workspaces diferentes da de desenvolvimento. Ver histórico completo
abaixo.

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
- **Stop K4SH1 Particle** e **Attach K4SH1 Particle to entity** — ver "Ideias futuras" abaixo.

### Ideias futuras (validadas, não implementadas)

- **Stop K4SH1 Particle** — parar uma instância em execução (ex.: uma aura). Precisa de um sistema
  de ID de instância e de um pacote de rede próprio do plugin — hoje todo spawn pega carona no
  pacote nativo de partícula do Minecraft, que não tem conceito de "parar depois". É o maior dos
  dois em esforço.
- **Attach K4SH1 Particle to entity** — prender um efeito a uma entidade em vez de a uma posição
  fixa, para que ele a acompanhe (aura, energia na mão, fogo nos pés). Escopo inicial acordado:
  **vanilla apenas, sem GeckoLib** — Player e entidades biped vanilla (zumbis, esqueletos) e o
  modelo biped padrão do MCreator. Pontos de ancoragem: raiz/corpo, cabeça, **olho**, braço/mão,
  perna/pé. Raiz/corpo/cabeça/olho é esforço baixo (a mesma máquina de `emitter_local_space` já
  existente, só ancorando num offset da entidade em vez de world-space). Braço/mão e perna/pé é
  esforço moderado (aproximar a pose de `HumanoidModel` via `entity.getAttackAnim(partialTick)` /
  `entity.walkAnimation`, API pública e estável do próprio Minecraft — sem precisar de GeckoLib
  nem mexer em internals de render). Suporte a GeckoLib, Player Animator e entidades não-biped
  fica para avaliação futura separada, possivelmente descartado.

### Fase 4 — Porte para MCreator 2026.2
Novos geradores: NeoForge 1.21.8, 26.1 e 26.2. Hoje o plugin implementa só o gerador
`neoforge-1.21.1` (ver [ARCHITECTURE.md](ARCHITECTURE.md)) — portar significa duplicar (ou
parametrizar) `src/neoforge-1.21.1/` para cada novo par gerador/versão, e revalidar que o
`runtime/` compila contra cada API de Minecraft alvo (o MoLang engine em `core/` não depende de
Minecraft, então essa parte deve migrar sem atrito).

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
