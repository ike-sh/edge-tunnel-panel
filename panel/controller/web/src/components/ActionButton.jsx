export default function ActionButton({ children, variant = 'primary', className = '', ...props }) {
  const cls = [variant === 'primary' ? '' : variant, className].filter(Boolean).join(' ');
  return <button className={cls} {...props}>{children}</button>;
}
