import {
  DndContext,
  KeyboardSensor,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
} from '@dnd-kit/core';
import {
  SortableContext,
  arrayMove,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import StatusBadge from './StatusBadge.jsx';

function ruleId(rule, index) {
  return rule.id || rule.rule_id || `rule-${index}`;
}

function SortableRuleRow({ rule, index, onEdit, onDelete }) {
  const id = ruleId(rule, index);
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.55 : 1,
  };

  return (
    <tr ref={setNodeRef} style={style} className={isDragging ? 'rule-row-dragging' : ''}>
      <td>
        <button
          type="button"
          className="drag-handle"
          aria-label="拖拽排序"
          {...attributes}
          {...listeners}
        >
          ⋮⋮
        </button>
      </td>
      <td><code>{id}</code></td>
      <td>{rule.nat_public_port || '-'}</td>
      <td>{rule.transit_port || '-'}</td>
      <td>{rule.local_port || '-'}</td>
      <td>{`${rule.landing_host || '-'}:${rule.landing_port || '-'}`}</td>
      <td>
        <StatusBadge status={rule.enabled !== false ? 'active' : 'inactive'}>
          {rule.enabled !== false ? '启用' : '禁用'}
        </StatusBadge>
      </td>
      <td>
        <div className="row-actions">
          <button type="button" className="small secondary" onClick={() => onEdit(rule)}>编辑</button>
          <button type="button" className="small danger" onClick={() => onDelete(rule)}>删除</button>
        </div>
      </td>
    </tr>
  );
}

export default function SortableRulesTable({ rules, onReorder, onEdit, onDelete, empty }) {
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const ids = rules.map((r, i) => ruleId(r, i));

  function handleDragEnd(event) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const oldIndex = ids.indexOf(active.id);
    const newIndex = ids.indexOf(over.id);
    if (oldIndex < 0 || newIndex < 0) return;
    onReorder(arrayMove(rules, oldIndex, newIndex));
  }

  if (!rules.length) {
    return <div className="empty-inline">{empty}</div>;
  }

  return (
    <div className="table-wrap">
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        <table className="data-table rules-sortable">
          <thead>
            <tr>
              <th aria-label="排序" />
              <th>规则 ID</th>
              <th>商家入口</th>
              <th>中转端口</th>
              <th>客户端入口</th>
              <th>落地</th>
              <th>状态</th>
              <th>操作</th>
            </tr>
          </thead>
          <tbody>
            <SortableContext items={ids} strategy={verticalListSortingStrategy}>
              {rules.map((rule, index) => (
                <SortableRuleRow
                  key={ids[index]}
                  rule={rule}
                  index={index}
                  onEdit={onEdit}
                  onDelete={onDelete}
                />
              ))}
            </SortableContext>
          </tbody>
        </table>
      </DndContext>
    </div>
  );
}
