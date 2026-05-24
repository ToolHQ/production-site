// GTA VI — Vice City Cluster Edition — Lógica do Jogo

// Estado do Jogo
let gameState = {
  money: 100,
  rep: 0,
  servers: 0,
  stars: 0,
  rank: "Estagiário de DevOps",
  name: "Reinaldinho"
};

// Configurações e Áudio Context
let audioCtx = null;
let isRadioPlaying = false;
let radioInterval = null;

// Ranks do Jogo baseados em Reputação
const RANKS = [
  { min: 0, title: "Estagiário de DevOps" },
  { min: 50, title: "Administrador de Sistemas Jr" },
  { min: 150, title: "Engenheiro SRE Pleno" },
  { min: 400, title: "Arquiteto Cloud Senior" },
  { min: 1000, title: "DevOps Godfather do Cluster" }
];

// Definição das Missões do Submundo
const MISSIONS = [
  {
    id: "mission-oracle-free",
    title: "Hackear Contas OCI Free Tier",
    desc: "Rodar script na calada da noite para contornar o limite do Oracle Cloud Infrastructure e criar 2 instâncias Ampere adicionais.",
    cost: 20,
    repReward: 10,
    moneyReward: 50,
    serversReward: 2,
    risk: 25, // 25% de chance de ganhar estrela
    minRep: 0
  },
  {
    id: "mission-hetzner-bypass",
    title: "Sequestrar Bare-Metal da Hetzner",
    desc: "Infiltrar um wrapper semântico nos runner nodes e desviar banda de rede excedente para minerar moedas.",
    cost: 50,
    repReward: 25,
    moneyReward: 120,
    serversReward: 1,
    risk: 40,
    minRep: 30
  },
  {
    id: "mission-logs-poisoning",
    title: "Envenenar Logs do Coroot",
    desc: "Injetar milhões de falsos positivos nos logs do ClickHouse para cegar a equipe de plantão (on-call) enquanto você faz alterações não autorizadas.",
    cost: 80,
    repReward: 40,
    moneyReward: 200,
    serversReward: 3,
    risk: 50,
    minRep: 100
  },
  {
    id: "mission-nexus-black-market",
    title: "Mercado Negro de Imagens no Nexus",
    desc: "Hospedar imagens Docker pirateadas de IA no registro local para vender acesso secreto a agentes autônomos rivais.",
    cost: 150,
    repReward: 80,
    moneyReward: 450,
    serversReward: 5,
    risk: 60,
    minRep: 250
  },
  {
    id: "mission-bypass-oci-billing",
    title: "Desativar Webhooks de Billing",
    desc: "Executar ataque direto a nível de rede no Ingress Controller para filtrar todas as notificações de cobrança da Oracle Cloud.",
    cost: 300,
    repReward: 200,
    moneyReward: 1000,
    serversReward: 8,
    risk: 80,
    minRep: 500
  }
];

// Inicialização
document.addEventListener("DOMContentLoaded", () => {
  loadGame();
  renderMissions();
  updateUI();

  // Listeners de Ação
  document.getElementById("radio-play-btn").addEventListener("click", toggleRadio);
  document.getElementById("reset-game-btn").addEventListener("click", resetGame);
});

// Funções de Persistência
function saveGame() {
  localStorage.setItem("gta_vi_cluster_save", JSON.stringify(gameState));
}

function loadGame() {
  const saved = localStorage.getItem("gta_vi_cluster_save");
  if (saved) {
    try {
      gameState = JSON.parse(saved);
      // Garantir integridade de campos se salvamentos antigos existirem
      if (!gameState.name) gameState.name = "Reinaldinho";
    } catch (e) {
      console.error("Falha ao ler save, iniciando do zero.");
    }
  }
}

function resetGame() {
  if (confirm("ATENÇÃO: Você perderá todo o seu progresso, créditos e servidores domados! Deseja mesmo formatar o banco de dados do GTA VI?")) {
    localStorage.removeItem("gta_vi_cluster_save");
    gameState = {
      money: 100,
      rep: 0,
      servers: 0,
      stars: 0,
      rank: "Estagiário de DevOps",
      name: "Reinaldinho"
    };
    if (isRadioPlaying) toggleRadio();
    saveGame();
    updateUI();
    renderMissions();
    
    // Limpar console logs
    const consoleLogs = document.getElementById("console-logs");
    consoleLogs.innerHTML = `<div class="log-entry system">[SISTEMA] Vice City Cluster formatado. Todos os segredos foram apagados!</div>`;
    addLog("Iniciando novo jogo como Estagiário de DevOps...", "warn");
  }
}

// Atualizar Interface Gráfica
function updateUI() {
  // Atualizar rank com base na reputação
  let currentRank = RANKS[0].title;
  for (let i = RANKS.length - 1; i >= 0; i--) {
    if (gameState.rep >= RANKS[i].min) {
      currentRank = RANKS[i].title;
      break;
    }
  }
  gameState.rank = currentRank;

  document.getElementById("player-name").innerText = gameState.name;
  document.getElementById("player-rank").innerText = gameState.rank;
  document.getElementById("stat-money").innerText = `$${gameState.money.toLocaleString()}`;
  document.getElementById("stat-rep").innerText = gameState.rep.toLocaleString();
  document.getElementById("stat-servers").innerText = gameState.servers.toLocaleString();

  // Renderizar estrelas de procurado
  const starContainer = document.getElementById("stat-stars");
  starContainer.innerHTML = "";
  for (let i = 0; i < 5; i++) {
    if (i < gameState.stars) {
      starContainer.innerHTML += "★";
    } else {
      starContainer.innerHTML += "☆";
    }
  }
}

// Logs no Console Cyberpunk
function addLog(message, type = "system") {
  const consoleLogs = document.getElementById("console-logs");
  const timeStr = new Date().toLocaleTimeString();
  const entry = document.createElement("div");
  entry.className = `log-entry ${type}`;
  entry.innerText = `[${timeStr}] ${message}`;
  consoleLogs.appendChild(entry);
  consoleLogs.scrollTop = consoleLogs.scrollHeight;
}

// Renderizar Missões Dinamicamente
function renderMissions() {
  const container = document.getElementById("missions-list");
  container.innerHTML = "";

  MISSIONS.forEach(m => {
    // Só renderiza se o jogador tiver a reputação mínima requerida
    if (gameState.rep >= m.minRep) {
      const card = document.createElement("div");
      card.className = "mission-card";
      
      const canAfford = gameState.money >= m.cost;
      const disableAttr = canAfford ? "" : "disabled";

      card.innerHTML = `
        <div class="mission-header">
          <span class="mission-title">${m.title}</span>
          <span class="mission-cost">Custo: $${m.cost}</span>
        </div>
        <p class="mission-desc">${m.desc}</p>
        <div class="mission-rewards">
          <span class="reward-item">📈 +${m.repReward} Rep</span>
          <span class="reward-item">💰 +$${m.moneyReward}</span>
          <span class="reward-item">🖥️ +${m.serversReward} Pods</span>
          <span class="reward-item">⚠️ Risco: ${m.risk}%</span>
        </div>
        <div class="mission-footer">
          <button class="btn btn-primary" ${disableAttr} onclick="runMission('${m.id}')">Executar Missão</button>
        </div>
      `;
      container.appendChild(card);
    }
  });
}

// Executar uma Missão
window.runMission = function(missionId) {
  const mission = MISSIONS.find(m => m.id === missionId);
  if (!mission) return;

  if (gameState.money < mission.cost) {
    addLog(`Fundos insuficientes para executar a missão: ${mission.title}`, "critical");
    return;
  }

  // Pagar custo
  gameState.money -= mission.cost;
  addLog(`Iniciando execução de: ${mission.title}. Custo de $${mission.cost} debitado.`, "system");

  // Simular latência de rede/hack (efeito imersivo)
  const buttons = document.querySelectorAll(".mission-card button");
  buttons.forEach(btn => btn.disabled = true);

  setTimeout(() => {
    // Determinar sucesso e risco
    const roll = Math.random() * 100;
    const gotBusted = roll < mission.risk;

    // Ganhar recompensas
    gameState.money += mission.moneyReward;
    gameState.rep += mission.repReward;
    gameState.servers += mission.serversReward;

    addLog(`Sucesso! Missão concluída: +$${mission.moneyReward}, +${mission.repReward} Rep, +${mission.serversReward} Pods dominados.`, "success");

    // Tocar efeito de sucesso sonoro se rádio estiver ligado
    if (isRadioPlaying && audioCtx) playFx(440, 660, 0.15);

    if (gotBusted) {
      if (gameState.stars < 5) {
        gameState.stars += 1;
        addLog(`CUIDADO: A equipe de segurança OCI/Billing detectou tráfego anômalo. Nível de Procurado subiu para ${gameState.stars} estrelas!`, "critical");
        if (isRadioPlaying && audioCtx) playFx(220, 110, 0.3);

        // Se atingir 5 estrelas, simular evasão/pagamento de suborno
        if (gameState.stars === 5) {
          const bribeCost = Math.floor(gameState.money * 0.4);
          gameState.money -= bribeCost;
          gameState.stars = 0;
          addLog(`OPERAÇÃO POLICIAL: OCI Admin bloqueou suas instâncias! Você subornou o auditor do Billing com $${bribeCost} para resetar suas estrelas de procurado!`, "critical");
        }
      }
    } else {
      // Evento aleatório benéfico ocasional se o risco não disparou
      if (Math.random() < 0.2 && gameState.stars > 0) {
        gameState.stars -= 1;
        addLog(`Os logs do syslog foram rotacionados. Seu nível de procurado diminuiu em 1 estrela.`, "success");
      }
    }

    saveGame();
    updateUI();
    renderMissions();
  }, 1000);
};

// --- ÁUDIO PROCEDURAL SYNTHWAVE COM WEB AUDIO API ---

function initAudio() {
  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
}

function playFx(freqStart, freqEnd, duration) {
  if (!audioCtx) return;
  try {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();

    osc.type = "sine";
    osc.frequency.setValueAtTime(freqStart, audioCtx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(freqEnd, audioCtx.currentTime + duration);

    gain.gain.setValueAtTime(0.1, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + duration);

    osc.connect(gain);
    gain.connect(audioCtx.destination);

    osc.start();
    osc.stop(audioCtx.currentTime + duration);
  } catch (e) {
    console.error("Falha ao tocar FX sonoro:", e);
  }
}

// Rádio Synthwave (Pulsador Synth e Baixo Sequenciador)
function toggleRadio() {
  if (!audioCtx) initAudio();

  const playBtn = document.getElementById("radio-play-btn");
  const wave = document.getElementById("sound-wave");

  if (!isRadioPlaying) {
    if (audioCtx.state === 'suspended') {
      audioCtx.resume();
    }
    
    isRadioPlaying = true;
    playBtn.innerText = "DESLIGAR RÁDIO";
    playBtn.classList.remove("btn-secondary");
    playBtn.classList.add("btn-primary");
    wave.classList.add("playing");
    
    startSynthLoop();
    addLog("Rádio K-CHAT conectada. Sintonizando clássicos Synthwave de Vice City...", "success");
  } else {
    isRadioPlaying = false;
    playBtn.innerText = "LIGAR RÁDIO";
    playBtn.classList.remove("btn-primary");
    playBtn.classList.add("btn-secondary");
    wave.classList.remove("playing");
    
    clearInterval(radioInterval);
    addLog("Rádio desligada.", "system");
  }
}

function startSynthLoop() {
  let beatCount = 0;
  
  // Notas da linha de baixo clássica synthwave (D3, F3, C3, G3)
  const bassNotes = [146.83, 146.83, 174.61, 174.61, 130.81, 130.81, 196.00, 196.00];
  // Notas de melodia retro
  const leadNotes = [293.66, 349.23, 392.00, 440.00, 392.00, 349.23];

  radioInterval = setInterval(() => {
    if (!isRadioPlaying || !audioCtx) return;

    try {
      const now = audioCtx.currentTime;

      // 1. LINHA DE BAIXO (Bassline a cada compasso de colcheia)
      const bassFreq = bassNotes[beatCount % bassNotes.length];
      const bassOsc = audioCtx.createOscillator();
      const bassGain = audioCtx.createGain();
      
      bassOsc.type = "sawtooth";
      bassOsc.frequency.setValueAtTime(bassFreq, now);
      
      bassGain.gain.setValueAtTime(0.08, now);
      bassGain.gain.exponentialRampToValueAtTime(0.005, now + 0.15);
      
      bassOsc.connect(bassGain);
      bassGain.connect(audioCtx.destination);
      bassOsc.start(now);
      bassOsc.stop(now + 0.18);

      // 2. BUMBO E CAIXA (Sintetizados)
      if (beatCount % 2 === 0) {
        // Bumbo no tempo 1 e 3
        const kickOsc = audioCtx.createOscillator();
        const kickGain = audioCtx.createGain();
        kickOsc.frequency.setValueAtTime(120, now);
        kickOsc.frequency.exponentialRampToValueAtTime(40, now + 0.1);
        
        kickGain.gain.setValueAtTime(0.18, now);
        kickGain.gain.exponentialRampToValueAtTime(0.01, now + 0.12);
        
        kickOsc.connect(kickGain);
        kickGain.connect(audioCtx.destination);
        kickOsc.start(now);
        kickOsc.stop(now + 0.13);
      } else {
        // Caixa no tempo 2 e 4 (ruído + frequência simulada)
        const snareOsc = audioCtx.createOscillator();
        const snareGain = audioCtx.createGain();
        snareOsc.type = "triangle";
        snareOsc.frequency.setValueAtTime(180, now);
        
        snareGain.gain.setValueAtTime(0.1, now);
        snareGain.gain.exponentialRampToValueAtTime(0.01, now + 0.15);
        
        snareOsc.connect(snareGain);
        snareGain.connect(audioCtx.destination);
        snareOsc.start(now);
        snareOsc.stop(now + 0.16);
      }

      // 3. LEAD MELODIA (Apenas a cada 4 batidas, simulando synth futurista)
      if (beatCount % 4 === 0) {
        const leadFreq = leadNotes[(beatCount / 4) % leadNotes.length];
        const leadOsc = audioCtx.createOscillator();
        const leadGain = audioCtx.createGain();
        
        leadOsc.type = "sine";
        leadOsc.frequency.setValueAtTime(leadFreq, now);
        
        leadGain.gain.setValueAtTime(0.04, now);
        leadGain.gain.exponentialRampToValueAtTime(0.001, now + 0.4);
        
        leadOsc.connect(leadGain);
        leadGain.connect(audioCtx.destination);
        leadOsc.start(now);
        leadOsc.stop(now + 0.45);
      }

      beatCount++;
    } catch (e) {
      console.error("Falha no sequenciador do rádio:", e);
    }
  }, 220); // Tempo BPM ajustado
}
