interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost'
}

export function Button({ variant = 'primary', className = '', children, ...props }: ButtonProps) {
  const base = 'font-headline font-semibold text-label-lg rounded min-h-touch w-full flex items-center justify-center active:scale-[0.98] transition-transform disabled:opacity-40'
  const variants = {
    primary: 'bg-primary text-on-primary',
    secondary: 'border border-outline text-on-surface',
    ghost: 'text-primary underline',
  }
  return (
    <button className={`${base} ${variants[variant]} ${className}`} {...props}>
      {children}
    </button>
  )
}
