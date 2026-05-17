import { h, Fragment } from 'preact';
import { useRef, useEffect, useState } from 'preact/hooks';
import styles from './DraggablePanel.module.css';

interface DraggablePanelProps {
  id: string;
  title: string;
  children: preact.ComponentChildren;
  onMove?: (x: number, y: number) => void;
  onResize?: (w: number, h: number) => void;
  x?: number;
  y?: number;
  w?: number;
  h?: number;
  isDraggable?: boolean;
  isResizable?: boolean;
}

export function DraggablePanel({
  id,
  title,
  children,
  onMove,
  onResize,
  x = 0,
  y = 0,
  w = 400,
  h = 300,
  isDraggable = true,
  isResizable = true,
}: DraggablePanelProps) {
  const panelRef = useRef<HTMLDivElement>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [isResizing, setIsResizing] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0, panelX: 0, panelY: 0 });
  const [resizeStart, setResizeStart] = useState({ x: 0, y: 0, w: 0, h: 0 });

  // Handle drag start (header)
  const handleDragStart = (e: MouseEvent) => {
    if (!isDraggable || !panelRef.current) return;
    setIsDragging(true);
    setDragStart({
      x: e.clientX,
      y: e.clientY,
      panelX: x,
      panelY: y,
    });
  };

  // Handle resize start (corner)
  const handleResizeStart = (e: MouseEvent) => {
    if (!isResizable || !panelRef.current) return;
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    setResizeStart({
      x: e.clientX,
      y: e.clientY,
      w,
      h,
    });
  };

  // Handle mouse move for drag/resize
  useEffect(() => {
    if (!isDragging && !isResizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      if (isDragging) {
        const deltaX = e.clientX - dragStart.x;
        const deltaY = e.clientY - dragStart.y;
        const newX = dragStart.panelX + deltaX;
        const newY = dragStart.panelY + deltaY;
        onMove?.(newX, newY);
      } else if (isResizing) {
        const deltaX = e.clientX - resizeStart.x;
        const deltaY = e.clientY - resizeStart.y;
        const newW = Math.max(300, resizeStart.w + deltaX);
        const newH = Math.max(200, resizeStart.h + deltaY);
        onResize?.(newW, newH);
      }
    };

    const handleMouseUp = () => {
      setIsDragging(false);
      setIsResizing(false);
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, isResizing, dragStart, resizeStart, onMove, onResize]);

  return (
    <div
      ref={panelRef}
      class={styles.panel}
      style={{
        left: `${x}px`,
        top: `${y}px`,
        width: `${w}px`,
        height: `${h}px`,
        position: 'absolute',
        zIndex: isDragging ? 1000 : 'auto',
      }}
    >
      <div
        class={styles.header}
        onMouseDown={isDraggable ? handleDragStart : undefined}
        style={{ cursor: isDraggable ? 'grab' : 'default' }}
      >
        <span class={styles.title}>{title}</span>
        {isDragging && <span class={styles.draggingIndicator}>Moving...</span>}
      </div>

      <div class={styles.content}>{children}</div>

      {isResizable && (
        <div
          class={styles.resizeHandle}
          onMouseDown={handleResizeStart}
          style={{ cursor: 'nwse-resize' }}
        />
      )}
    </div>
  );
}
