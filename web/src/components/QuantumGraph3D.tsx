import { Component, ReactNode, useMemo, useRef, useState } from "react";
import { Canvas, useFrame } from "@react-three/fiber";
import { Html, Line, OrbitControls, Stars } from "@react-three/drei";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import * as THREE from "three";
import { forceCenter, forceLink, forceManyBody, forceSimulation } from "d3-force-3d";

export interface GNode { id: string; label: string; color: string; size: number; glow: number; tooltip: string[] }
export interface GEdge { source: string; target: string; weight: number }

interface Props {
  nodes: GNode[]; edges: GEdge[]; flow?: number[][]; selected?: string | null; onSelect?: (id: string) => void;
  accent: string; muted: string; dark: boolean; reducedMotion: boolean; height?: number;
}

type Pos = Record<string, THREE.Vector3>;

/** Stable 3D force layout; recomputed only when the graph topology changes. */
function useLayout(nodes: GNode[], edges: GEdge[]): Pos {
  const key = nodes.map((n) => n.id).join(",") + "|" + edges.map((e) => `${e.source}-${e.target}`).join(",");
  return useMemo(() => {
    const sn = nodes.map((n) => ({ id: n.id })) as { id: string; x?: number; y?: number; z?: number }[];
    const sl = edges.map((e) => ({ source: e.source, target: e.target, w: e.weight }));
    const sim = forceSimulation(sn, 3)
      .force("link", forceLink(sl).id((d: { id: string }) => d.id).distance((l: { w: number }) => 2.6 - 1.4 * l.w).strength(0.7))
      .force("charge", forceManyBody().strength(-14))
      .force("center", forceCenter(0, 0, 0))
      .stop();
    for (let i = 0; i < 400; i++) sim.tick();
    const r = Math.max(...sn.map((p) => Math.hypot(p.x!, p.y!, p.z!)), 1e-6);
    return Object.fromEntries(sn.map((p) => [p.id, new THREE.Vector3(p.x!, p.y!, p.z!).multiplyScalar(4.4 / r)]));   // fits the view: tan(22.5°) × 12 ≈ 5.0 > 4.4 + node size
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
}

function NodeMesh({ n, p, active, onHover, onClick, dark }: {
  n: GNode; p: THREE.Vector3; active: boolean; onHover: (id: string | null) => void; onClick: () => void; dark: boolean;
}) {
  const mesh = useRef<THREE.Mesh>(null!);
  const mat = useRef<THREE.MeshStandardMaterial>(null!);
  const target = useMemo(() => new THREE.Color(n.color), [n.color]);
  useFrame((_, dt) => {
    const k = 1 - Math.exp(-dt * 7);
    const s = n.size * (active ? 1.35 : 1);
    mesh.current.scale.lerp(new THREE.Vector3(s, s, s), k);
    mat.current.color.lerp(target, k);
    mat.current.emissive.lerp(target, k);
    mat.current.emissiveIntensity += ((dark ? 0.35 : 0.15) + n.glow * (dark ? 2.4 : 0.8) - mat.current.emissiveIntensity) * k;
  });
  return (
    <group position={p}>
      <mesh ref={mesh} onPointerOver={(e) => { e.stopPropagation(); onHover(n.id); }} onPointerOut={() => onHover(null)}
            onClick={(e) => { e.stopPropagation(); onClick(); }}>
        <sphereGeometry args={[1, 40, 40]} />
        <meshStandardMaterial ref={mat} roughness={0.32} metalness={0.15} toneMapped={false} />
      </mesh>
      <Html position={[0, n.size + 0.28, 0]} center distanceFactor={11} zIndexRange={[10, 0]} style={{ pointerEvents: "none" }}>
        <div className={`whitespace-nowrap rounded px-1 text-[11px] font-medium ${active ? "text-accent" : "text-ink/80"}`}
             style={{ textShadow: dark ? "0 0 6px rgba(0,0,0,.9)" : "0 0 4px rgba(255,255,255,.9)" }}>{n.label}</div>
      </Html>
    </group>
  );
}

/** Particles travelling along links; density and speed follow the walk's transition probability. */
function Flow({ edges, pos, flow, index, accent, reducedMotion }: {
  edges: GEdge[]; pos: Pos; flow?: number[][]; index: Record<string, number>; accent: string; reducedMotion: boolean;
}) {
  const parts = useMemo(() => {
    if (!flow) return [];
    const f = edges.map((e) => { const i = index[e.source], j = index[e.target]; return (flow[i]?.[j] ?? 0) + (flow[j]?.[i] ?? 0); });
    const fmax = Math.max(...f, 1e-9);
    const out: { a: THREE.Vector3; b: THREE.Vector3; phase: number; speed: number }[] = [];
    edges.forEach((e, k) => {
      const z = f[k] / fmax, n = 1 + Math.round(z * 3);
      for (let m = 0; m < n; m++) {
        const fwd = m % 2 === 0;
        out.push({ a: fwd ? pos[e.source] : pos[e.target], b: fwd ? pos[e.target] : pos[e.source], phase: Math.random(), speed: 0.08 + 0.42 * z });
      }
    });
    return out;
  }, [edges, pos, flow, index]);
  const ref = useRef<THREE.InstancedMesh>(null!);
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const t = useRef(0);
  useFrame((_, dt) => {
    if (!ref.current) return;
    if (!reducedMotion) t.current += dt;
    parts.forEach((p, i) => {
      const u = (p.phase + t.current * p.speed) % 1;
      dummy.position.lerpVectors(p.a, p.b, u);
      const s = 0.03 + 0.04 * Math.sin(Math.PI * u);
      dummy.scale.setScalar(s);
      dummy.updateMatrix();
      ref.current.setMatrixAt(i, dummy.matrix);
    });
    ref.current.instanceMatrix.needsUpdate = true;
  });
  if (!parts.length) return null;
  return (
    <instancedMesh key={parts.length} ref={ref} args={[undefined, undefined, parts.length]}>
      <sphereGeometry args={[1, 10, 10]} />
      <meshBasicMaterial color={accent} toneMapped={false} />
    </instancedMesh>
  );
}

function Scene({ nodes, edges, flow, selected, onSelect, accent, muted, dark, reducedMotion }: Props) {
  const pos = useLayout(nodes, edges);
  const index = useMemo(() => Object.fromEntries(nodes.map((n, i) => [n.id, i])), [nodes]);
  const [hover, setHover] = useState<string | null>(null);
  const focus = hover ?? selected ?? null;
  const hn = nodes.find((n) => n.id === hover);
  return (
    <>
      <ambientLight intensity={dark ? 0.35 : 0.9} />
      <pointLight position={[10, 12, 10]} intensity={dark ? 120 : 160} />
      <pointLight position={[-12, -8, -6]} intensity={40} color={accent} />
      {dark && <Stars radius={60} depth={30} count={1800} factor={3} saturation={0} fade speed={reducedMotion ? 0 : 0.4} />}
      {edges.map((e, k) => {
        const on = focus && (e.source === focus || e.target === focus);
        return pos[e.source] && pos[e.target] ? (
          <Line key={k} points={[pos[e.source], pos[e.target]]} color={on ? accent : muted}
                lineWidth={on ? 1.6 + 2 * e.weight : 0.6 + 1.6 * e.weight} transparent opacity={on ? 0.95 : 0.22 + 0.45 * e.weight} />
        ) : null;
      })}
      <Flow edges={edges} pos={pos} flow={flow} index={index} accent={accent} reducedMotion={reducedMotion} />
      {nodes.map((n) => pos[n.id] && (
        <NodeMesh key={n.id} n={n} p={pos[n.id]} active={n.id === focus} dark={dark} onHover={setHover} onClick={() => onSelect?.(n.id)} />
      ))}
      {hn && (
        <Html position={pos[hn.id].clone().add(new THREE.Vector3(0, -hn.size - 0.4, 0))} center zIndexRange={[20, 10]} style={{ pointerEvents: "none" }}>
          <div className="glass min-w-[180px] px-3 py-2 text-xs leading-5 text-ink shadow-2xl">
            <div className="mb-0.5 font-semibold">{hn.label}</div>
            {hn.tooltip.map((t) => <div key={t} className="num text-muted">{t}</div>)}
          </div>
        </Html>
      )}
      <OrbitControls enablePan={false} enableDamping minDistance={6} maxDistance={22} autoRotate={!reducedMotion && !hover} autoRotateSpeed={0.45} />
      {dark && (
        <EffectComposer>
          <Bloom mipmapBlur intensity={0.9} luminanceThreshold={0.18} luminanceSmoothing={0.3} />
        </EffectComposer>
      )}
    </>
  );
}

class GLBoundary extends Component<{ children: ReactNode }, { err: boolean }> {
  state = { err: false };
  static getDerivedStateFromError() { return { err: true }; }
  render() {
    return this.state.err
      ? <div className="grid h-full place-items-center p-6 text-center text-sm text-muted">3D view unavailable (WebGL is disabled in this browser). The table and charts still show every value.</div>
      : this.props.children;
  }
}

export default function QuantumGraph3D(props: Props) {
  return (
    <div style={{ height: props.height ?? 520 }} className="relative">
      <GLBoundary>
        <Canvas camera={{ position: [0, 0.8, 12], fov: 45 }} dpr={[1, 2]} gl={{ antialias: true, alpha: true }}>
          <Scene {...props} />
        </Canvas>
      </GLBoundary>
    </div>
  );
}
