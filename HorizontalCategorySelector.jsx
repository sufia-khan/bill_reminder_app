import React, { useState, useRef, useEffect } from 'react';
import {
  FaCreditCard,
  FaHome,
  FaWifi,
  FaSchool,
  FaBolt,
  FaHeartbeat,
  FaCar,
  FaFilm,
  FaUtensils,
  FaShoppingBag,
  FaHospital,
  FaDumbbell,
  FaEllipsisH
} from 'react-icons/fa';

interface Category {
  id: string;
  name: string;
  icon: React.ReactNode;
}

interface HorizontalCategorySelectorProps {
  categories?: Category[];
  onCategoryChange?: (categoryId: string) => void;
  className?: string;
}

const HorizontalCategorySelector: React.FC<HorizontalCategorySelectorProps> = ({
  categories: propCategories,
  onCategoryChange,
  className = ""
}) => {
  const [activeCategory, setActiveCategory] = useState<string>('all');
  const scrollContainerRef = useRef<HTMLDivElement>(null);
  const [isAutoScrolling, setIsAutoScrolling] = useState(false);

  // Default categories
  const defaultCategories: Category[] = [
    { id: 'all', name: 'All', icon: <FaEllipsisH /> },
    { id: 'subscription', name: 'Subscription', icon: <FaCreditCard /> },
    { id: 'utilities', name: 'Utilities', icon: <FaBolt /> },
    { id: 'internet', name: 'Internet', icon: <FaWifi /> },
    { id: 'rent', name: 'Rent', icon: <FaHome /> },
    { id: 'credit-card', name: 'Credit Card', icon: <FaCreditCard /> },
    { id: 'shopping', name: 'Shopping', icon: <FaShoppingBag /> },
    { id: 'gym', name: 'Gym', icon: <FaDumbbell /> },
    { id: 'education', name: 'Education', icon: <FaSchool /> },
    { id: 'insurance', name: 'Insurance', icon: <FaHeartbeat /> },
    { id: 'transport', name: 'Transport', icon: <FaCar /> },
    { id: 'entertainment', name: 'Entertainment', icon: <FaFilm /> },
    { id: 'food', name: 'Food & Dining', icon: <FaUtensils /> },
    { id: 'health', name: 'Health', icon: <FaHospital /> },
    { id: 'other', name: 'Other', icon: <FaEllipsisH /> },
  ];

  const categories = propCategories || defaultCategories;

  const handleCategoryClick = (categoryId: string) => {
    setActiveCategory(categoryId);
    if (onCategoryChange) {
      onCategoryChange(categoryId);
    }
  };

  const checkScrollPosition = () => {
    if (!scrollContainerRef.current || isAutoScrolling) return;

    const container = scrollContainerRef.current;
    const scrollLeft = container.scrollLeft;
    const scrollWidth = container.scrollWidth;
    const clientWidth = container.clientWidth;

    // If scrolled to near the end, auto-scroll to show more
    if (scrollLeft + clientWidth >= scrollWidth - 100) {
      setIsAutoScrolling(true);
      const targetScroll = Math.min(scrollLeft + 200, scrollWidth - clientWidth);

      container.scrollTo({
        left: targetScroll,
        behavior: 'smooth'
      });

      setTimeout(() => {
        setIsAutoScrolling(false);
      }, 300);
    }
  };

  useEffect(() => {
    const container = scrollContainerRef.current;
    if (container) {
      container.addEventListener('scroll', checkScrollPosition);
      return () => {
        container.removeEventListener('scroll', checkScrollPosition);
      };
    }
  }, [isAutoScrolling]);

  return (
    <div className={`w-full bg-gray-50 rounded-2xl p-4 ${className}`}>
      <div
        ref={scrollContainerRef}
        className="flex gap-3 overflow-x-auto scrollbar-hide"
        style={{
          scrollbarWidth: 'none',
          msOverflowStyle: 'none'
        }}
      >
        {categories.map((category) => {
          const isActive = activeCategory === category.id;

          return (
            <button
              key={category.id}
              onClick={() => handleCategoryClick(category.id)}
              className={`
                flex items-center gap-2 px-4 py-2 rounded-lg transition-all duration-200
                whitespace-nowrap flex-shrink-0
                ${isActive
                  ? 'bg-blue-600 text-white shadow-md'
                  : 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                }
              `}
            >
              {/* Show icon only when active */}
              {isActive && (
                <span className="text-white">
                  {category.icon}
                </span>
              )}
              <span className={`font-medium ${isActive ? 'text-white' : 'text-gray-600'}`}>
                {category.name}
              </span>
            </button>
          );
        })}
      </div>

      {/* Hide scrollbar for Webkit browsers */}
      <style jsx>{`
        .scrollbar-hide::-webkit-scrollbar {
          display: none;
        }

        .scrollbar-hide {
          -ms-overflow-style: none;
          scrollbar-width: none;
        }
      `}</style>
    </div>
  );
};

export default HorizontalCategorySelector;