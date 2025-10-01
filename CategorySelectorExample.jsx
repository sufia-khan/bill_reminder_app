import React, { useState } from 'react';
import HorizontalCategorySelector from './HorizontalCategorySelector';
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

const CategorySelectorExample = () => {
  const [selectedCategory, setSelectedCategory] = useState('all');

  // Sample data that would be filtered based on category
  const sampleBills = [
    { id: 1, name: 'Netflix Subscription', amount: '$15.99', category: 'subscription' },
    { id: 2, name: 'Electric Bill', amount: '$120.00', category: 'utilities' },
    { id: 3, name: 'Internet Service', amount: '$79.99', category: 'internet' },
    { id: 4, name: 'Rent Payment', amount: '$1,500.00', category: 'rent' },
    { id: 5, name: 'Shopping', amount: '$45.00', category: 'shopping' },
    { id: 6, name: 'Gym Membership', amount: '$35.00', category: 'gym' },
  ];

  const filteredBills = selectedCategory === 'all'
    ? sampleBills
    : sampleBills.filter(bill => bill.category === selectedCategory);

  const handleCategoryChange = (categoryId) => {
    setSelectedCategory(categoryId);
    console.log(`Selected category: ${categoryId}`);
  };

  return (
    <div className="min-h-screen bg-gray-100 p-6">
      <div className="max-w-4xl mx-auto">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">Bill Manager</h1>
        <p className="text-gray-600 mb-6">Manage your bills and subscriptions</p>

        {/* Category Selector */}
        <div className="mb-8">
          <h2 className="text-lg font-semibold text-gray-700 mb-3">Categories</h2>
          <HorizontalCategorySelector
            onCategoryChange={handleCategoryChange}
          />
        </div>

        {/* Filtered Results */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-gray-700">
              {selectedCategory === 'all' ? 'All Bills' : `${selectedCategory.charAt(0).toUpperCase() + selectedCategory.slice(1)} Bills`}
            </h2>
            <span className="text-sm text-gray-500">
              {filteredBills.length} items
            </span>
          </div>

          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {filteredBills.map((bill) => (
              <div
                key={bill.id}
                className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 hover:shadow-md transition-shadow"
              >
                <div className="flex items-center justify-between mb-2">
                  <h3 className="font-medium text-gray-800">{bill.name}</h3>
                  <span className="text-lg font-semibold text-blue-600">{bill.amount}</span>
                </div>
                <div className="flex items-center text-sm text-gray-500">
                  <span className="bg-gray-100 px-2 py-1 rounded-full text-xs">
                    {bill.category}
                  </span>
                </div>
              </div>
            ))}
          </div>

          {filteredBills.length === 0 && (
            <div className="text-center py-8">
              <div className="text-gray-400 mb-2">No bills found</div>
              <p className="text-sm text-gray-500">
                Try selecting a different category or add a new bill
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default CategorySelectorExample;